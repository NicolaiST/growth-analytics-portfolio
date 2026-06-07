-- sp_transform_marketing_data.sql
-- Stored procedure wrapper for fct_marketing_performance.
-- Joins daily channel performance to B2B funnel conversion data
-- and computes all marketing efficiency metrics at campaign/channel/day level.
--
-- Execute: CALL `growth-dashboard-portfolio.marketing_data.sp_transform_marketing_data`();
--
-- Output table: marketing_data.fct_marketing_performance
-- Run after: gen_marketing_perf_raw, gen_conversions_raw
-- Run before: sp_analytics_mmm_prep (depends on fct_marketing_performance)

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_transform_marketing_data`()
OPTIONS(strict_mode=false)
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_performance` AS

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
      CASE
        WHEN channel IN ('Organic Search', 'Email') THEN FALSE
        ELSE TRUE
      END AS is_paid_channel
    FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
  ),

  daily_conversions AS (
    SELECT
      conversion_date                                                       AS date,
      campaign_id,
      COUNT(*)                                                              AS total_conversions,
      COUNT(CASE WHEN conversion_type = 'MQL'           THEN 1 END)        AS mql_count,
      COUNT(CASE WHEN conversion_type = 'Demo Request'  THEN 1 END)        AS demo_request_count,
      COUNT(CASE WHEN conversion_type = 'Trial Sign-up' THEN 1 END)        AS trial_count,
      COUNT(CASE WHEN conversion_type = 'Closed Won'    THEN 1 END)        AS closed_won_count,
      SUM(CASE WHEN conversion_type = 'Closed Won'
            THEN revenue ELSE 0.0 END)                                     AS attributed_revenue
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
    GROUP BY 1, 2
  ),

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
      COALESCE(dc.total_conversions,  0)                                   AS total_conversions,
      COALESCE(dc.mql_count,          0)                                   AS mql_count,
      COALESCE(dc.demo_request_count, 0)                                   AS demo_request_count,
      COALESCE(dc.trial_count,        0)                                   AS trial_count,
      COALESCE(dc.closed_won_count,   0)                                   AS closed_won_count,
      COALESCE(dc.attributed_revenue, 0.0)                                 AS attributed_revenue
    FROM base_performance bp
    LEFT JOIN daily_conversions dc
      ON  bp.date        = dc.date
      AND bp.campaign_id = dc.campaign_id
  ),

  enriched AS (
    SELECT
      date,
      campaign_id,
      channel,
      source_medium,
      is_paid_channel,
      impressions,
      clicks,
      sessions,
      spend,
      spend                                                                AS platform_reported_spend,
      COALESCE(spend, 0.0)                                                 AS analytical_spend,
      GREATEST(COALESCE(clicks, 0) - COALESCE(sessions, 0), 0)            AS click_dropoff_volume,
      total_conversions,
      mql_count,
      demo_request_count,
      trial_count,
      closed_won_count,
      attributed_revenue,
      ROUND(SAFE_DIVIDE(clicks, NULLIF(impressions, 0)) * 100, 4)         AS click_through_rate,
      ROUND(SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(clicks, 0)), 2)      AS cost_per_click,
      ROUND(SAFE_DIVIDE(total_conversions, NULLIF(sessions, 0)) * 100, 4) AS conversion_rate,
      ROUND(SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(mql_count, 0)), 2)   AS cost_per_mql,
      ROUND(SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(demo_request_count, 0)), 2) AS cost_per_demo,
      ROUND(
        AVG(COALESCE(spend, 0.0)) OVER (
          PARTITION BY campaign_id
          ORDER BY date
          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
      )                                                                    AS rolling_7day_avg_spend
    FROM joined
  )

  SELECT
    date,
    campaign_id,
    channel,
    source_medium,
    is_paid_channel,
    impressions,
    clicks,
    sessions,
    spend,
    platform_reported_spend,
    analytical_spend,
    click_dropoff_volume,
    total_conversions,
    mql_count,
    demo_request_count,
    trial_count,
    closed_won_count,
    attributed_revenue,
    click_through_rate,
    cost_per_click,
    conversion_rate,
    cost_per_mql,
    cost_per_demo,
    rolling_7day_avg_spend,
    CASE
      WHEN is_paid_channel = FALSE THEN NULL
      ELSE ROUND(SAFE_DIVIDE(COALESCE(spend, 0.0), NULLIF(closed_won_count, 0)), 2)
    END                                                                    AS cac,
    CASE
      WHEN is_paid_channel = FALSE THEN NULL
      ELSE ROUND(SAFE_DIVIDE(attributed_revenue, NULLIF(COALESCE(spend, 0.0), 0)), 4)
    END                                                                    AS roas
  FROM enriched
  ORDER BY date DESC, campaign_id ASC;

END;
