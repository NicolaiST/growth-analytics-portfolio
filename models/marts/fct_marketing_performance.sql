-- fct_marketing_performance.sql
-- Core B2B SaaS marketing performance fact table.
-- Central mart model that sits between the staging layer and all downstream
-- consumers: MMM features, budget pacing, Looker Studio dashboards, and ML models.
--
-- This table joins daily channel performance (spend, impressions, clicks, sessions)
-- with attributed conversion and revenue data from the conversion funnel,
-- and computes all standard B2B marketing efficiency metrics in one place.
--
-- B2B context:
--   Metrics are calculated at campaign/channel/day granularity.
--   Attribution model used: last-touch (campaign_id on conversion event).
--   In production, a multi-touch attribution model would distribute
--   conversion credit across all touchpoints in the user journey.
--
--   CAC is calculated as spend / closed_won_count. In B2B this is the
--   commercially meaningful CAC — not spend per MQL or per trial,
--   which would dramatically understate true acquisition cost.
--
-- Derived fields reference:
--   click_through_rate      = clicks / impressions (paid channels only)
--   cost_per_click          = spend / clicks
--   conversion_rate         = total_conversions / sessions
--   cac                     = spend / closed_won_count (NULL for zero-cost channels)
--   cost_per_mql            = spend / mql_count
--   cost_per_demo           = spend / demo_request_count
--   rolling_7day_avg_spend  = 7-day moving average spend (smooths bursty channels)
--   click_dropoff_volume    = clicks - sessions (users who clicked but didn't session)
--
-- Known limitations (production enhancements flagged):
--   1. ATTRIBUTION: Last-touch only. Multi-touch would require an event_touchpoints
--      table with user-level journey data and a weighting algorithm.
--   2. REVENUE LAG: Closed Won revenue is attributed on conversion_date.
--      Production would align to contract start date for accurate ARR recognition.
--   3. STORED PROCEDURE: Requires manual execution. Production equivalent
--      would be a dbt model scheduled to run daily after source tables refresh.
--
-- Sources:
--   staging: stg_marketing_performance  (channel spend + engagement metrics)
--   staging: stg_conversions            (B2B funnel conversion events)
--   dimension: dim_campaigns            (campaign_id → channel lookup)
-- Output: marketing_data.fct_marketing_performance

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_transform_marketing_data`()
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_performance` AS

  -- 1. Clean base: pull from staging (nulls already handled via COALESCE)
  WITH base_performance AS (
    SELECT
      date,
      campaign_id,
      channel,
      source_medium,
      impressions,
      clicks,
      spend,
      sessions,
      is_paid_channel
    FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
  ),

  -- 2. Aggregate B2B funnel conversions by campaign and date
  --    Splits conversion_raw into funnel stage buckets for granular cost metrics.
  --    All revenue comes from Closed Won events only — pre-revenue stages
  --    are counted for funnel velocity analysis but carry £0 revenue.
  daily_conversions AS (
    SELECT
      conversion_date                                                     AS date,
      campaign_id,
      COUNT(*)                                                            AS total_conversions,
      COUNT(CASE WHEN conversion_type = 'MQL'           THEN 1 END)      AS mql_count,
      COUNT(CASE WHEN conversion_type = 'Demo Request'  THEN 1 END)      AS demo_request_count,
      COUNT(CASE WHEN conversion_type = 'Trial Sign-up' THEN 1 END)      AS trial_count,
      COUNT(CASE WHEN conversion_type = 'Closed Won'    THEN 1 END)      AS closed_won_count,
      -- Revenue only from Closed Won — pre-revenue stages contribute £0
      SUM(CASE WHEN conversion_type = 'Closed Won'
            THEN revenue ELSE 0.0 END)                                   AS attributed_revenue
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
    GROUP BY 1, 2
  ),

  -- 3. Join performance to conversions
  --    LEFT JOIN preserves days with spend but zero conversions —
  --    common in B2B where deal cycles mean spend and conversion
  --    events rarely align to the same day
  joined AS (
    SELECT
      bp.date,
      bp.campaign_id,
      bp.channel,
      bp.source_medium,
      bp.impressions,
      bp.clicks,
      bp.spend,
      bp.sessions,
      bp.is_paid_channel,
      COALESCE(dc.total_conversions,   0)                                AS total_conversions,
      COALESCE(dc.mql_count,           0)                                AS mql_count,
      COALESCE(dc.demo_request_count,  0)                                AS demo_request_count,
      COALESCE(dc.trial_count,         0)                                AS trial_count,
      COALESCE(dc.closed_won_count,    0)                                AS closed_won_count,
      COALESCE(dc.attributed_revenue,  0.0)                              AS attributed_revenue
    FROM base_performance bp
    LEFT JOIN daily_conversions dc
      ON  bp.date        = dc.date
      AND bp.campaign_id = dc.campaign_id
  )

  -- 4. Final output: compute all derived efficiency metrics
  SELECT
    date,
    campaign_id,
    channel,
    source_medium,
    is_paid_channel,

    -- Raw engagement metrics
    impressions,
    clicks,
    sessions,
    spend,

    -- Platform spend vs modelled spend
    -- platform_reported_spend preserves the raw value pre-COALESCE
    -- for reconciliation purposes; spend is the clean analytical field
    spend                                                                AS platform_reported_spend,
    COALESCE(spend, 0.0)                                                 AS analytical_spend,

    -- Click dropoff: users who clicked the ad but did not generate a session
    -- Indicates landing page issues, bot traffic, or tracking gaps
    GREATEST(COALESCE(clicks, 0) - COALESCE(sessions, 0), 0)            AS click_dropoff_volume,

    -- B2B funnel conversion counts
    total_conversions,
    mql_count,
    demo_request_count,
    trial_count,
    closed_won_count,
    attributed_revenue,

    -- Engagement efficiency metrics
    -- SAFE_DIVIDE used throughout to handle zero denominators gracefully
    ROUND(
      SAFE_DIVIDE(clicks, NULLIF(impressions, 0)) * 100, 4
    )                                                                    AS click_through_rate,

    ROUND(
      SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(clicks, 0)), 2
    )                                                                    AS cost_per_click,

    ROUND(
      SAFE_DIVIDE(total_conversions, NULLIF(sessions, 0)) * 100, 4
    )                                                                    AS conversion_rate,

    -- B2B funnel cost metrics
    -- cost_per_mql: spend per marketing qualified lead
    ROUND(
      SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(mql_count, 0)), 2
    )                                                                    AS cost_per_mql,

    -- cost_per_demo: spend per demo request (high-intent B2B metric)
    ROUND(
      SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(demo_request_count, 0)), 2
    )                                                                    AS cost_per_demo,

    -- cac: customer acquisition cost — spend per closed won deal
    -- Most commercially meaningful CAC metric in B2B
    -- NULL for zero-cost channels (Organic, Email) as no media spend
    CASE
      WHEN is_paid_channel = FALSE THEN NULL
      ELSE ROUND(
        SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(closed_won_count, 0)), 2
      )
    END                                                                  AS cac,

    -- roas: return on ad spend (attributed revenue / spend)
    -- NULL for zero-cost channels
    CASE
      WHEN is_paid_channel = FALSE THEN NULL
      ELSE ROUND(
        SAFE_DIVIDE(attributed_revenue, NULLIF(COALESCE(spend, 0.0), 0)), 4
      )
    END                                                                  AS roas,

    -- 7-day rolling average spend: smooths bursty channels (Events, LinkedIn)
    -- and provides a stable trend line for pacing and forecasting
    ROUND(
      AVG(COALESCE(spend, 0.0)) OVER (
        PARTITION BY campaign_id
        ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
      ), 2
    )                                                                    AS rolling_7day_avg_spend

  FROM joined
  ORDER BY date DESC, campaign_id ASC;

END;
