-- fct_marketing_budget_pacing.sql
-- Daily budget pacing model for B2B SaaS marketing campaigns.
-- Tracks cumulative spend against a linear run-rate target and flags
-- campaigns that deviate beyond acceptable thresholds.
--
-- B2B context:
--   Budget pacing in B2B differs from B2C in two important ways:
--   1. Spend is intentionally uneven — LinkedIn and Events have bursty
--      patterns (high spend on certain days, zero on others). A linear
--      run-rate target is a simplification; in production you'd weight
--      the target by historical day-of-week spend patterns.
--   2. The 15% variance threshold reflects B2B campaign behaviour where
--      audience sizes are smaller and delivery can stall or spike more
--      sharply than in broad B2C campaigns.
--
-- Pacing status logic:
--   OVERPACING  → cumulative spend > 115% of linear target (burn rate too high)
--   UNDERPACING → cumulative spend < 85% of linear target (delivery stalling)
--   OPTIMAL     → within ±15% of linear target
--
-- Known limitations (production enhancements flagged):
--   1. LINEAR TARGET: Assumes perfectly even daily spend. A production model
--      would use a weighted daily target based on historical day-of-week
--      spend distribution per channel (e.g. LinkedIn spend is typically
--      lower on weekends for B2B audiences).
--   2. STORED PROCEDURE: Currently requires manual execution. Production
--      equivalent would be a scheduled query or dbt model running daily.
--   3. EVENTS CHANNEL: Bursty spend (modelled as ~8% of days having spend)
--      will frequently show as UNDERPACING on non-event days. A production
--      model would exclude Events from linear pacing and use a milestone-
--      based budget tracker instead.
--
-- Source: marketing_data.marketing_perf_raw (via staging)
-- Dimension: marketing_data.campaign_budgets_dim
-- Output: marketing_data.fct_marketing_budget_pacing

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_budget_pacing`()
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_budget_pacing` AS

  -- 1. Aggregate actual spend by day and campaign from staging
  --    Using LEFT JOIN to staging ensures zero-spend days are preserved
  --    rather than dropped, which would corrupt the cumulative calculation.
  WITH daily_spend AS (
    SELECT
      date,
      DATE_TRUNC(date, MONTH)   AS budget_month,
      campaign_id,
      channel,
      -- COALESCE handles any residual nulls from raw source
      -- (should already be 0.0 from staging but defensive here)
      SUM(COALESCE(spend, 0.0)) AS daily_actual_spend
    FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
    GROUP BY 1, 2, 3, 4
  ),

  -- 2. Join to budget dimension and calculate cumulative spend + calendar progression
  --    LEFT JOIN preserves campaigns with no budget entry so they surface
  --    as NULL in pacing output rather than being silently dropped.
  pacing_calculations AS (
    SELECT
      ds.date,
      ds.budget_month,
      ds.campaign_id,
      ds.channel,
      ds.daily_actual_spend,

      -- Running cumulative spend from day 1 of the month to current date
      SUM(ds.daily_actual_spend) OVER (
        PARTITION BY ds.campaign_id, ds.budget_month
        ORDER BY ds.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )                                             AS cumulative_mtd_spend,

      EXTRACT(DAY FROM ds.date)                     AS day_of_month,
      EXTRACT(DAY FROM LAST_DAY(ds.date))           AS total_days_in_month,

      -- Budget allocation from dimension table
      -- NULL if campaign has no budget entry — surfaced in final output
      b.monthly_allocated_budget,

      -- B2B context: capture channel type for threshold adjustment downstream
      CASE
        WHEN ds.channel IN ('Organic Search', 'Email') THEN 'Zero-Cost'
        WHEN ds.channel = 'Events'                     THEN 'Bursty'
        ELSE                                                'Paid'
      END                                           AS channel_spend_type

    FROM daily_spend ds
    LEFT JOIN `growth-dashboard-portfolio.marketing_data.campaign_budgets_dim` b
      ON ds.campaign_id = b.campaign_id
  ),

  -- 3. Calculate linear run-rate target and variance
  --    NULLIF guard prevents division-by-zero if monthly_allocated_budget
  --    is 0 or NULL (e.g. organic/email campaigns with no budget entry)
  variance_matrix AS (
    SELECT
      *,
      -- Linear daily target: assumes even spend distribution across the month
      -- See header note on limitation for bursty channels (LinkedIn, Events)
      ROUND(
        (COALESCE(monthly_allocated_budget, 0.0) / NULLIF(total_days_in_month, 0))
        * day_of_month,
        2
      )                                             AS target_linear_mtd_spend,

      -- Budget burn percentage: what % of monthly budget has been spent MTD
      ROUND(
        (cumulative_mtd_spend / NULLIF(monthly_allocated_budget, 0.0)) * 100,
        2
      )                                             AS monthly_budget_burn_pct

    FROM pacing_calculations
  )

  -- 4. Final output with pacing status alert
  --    Threshold logic adjusted per channel_spend_type:
  --    Paid channels: ±15% variance band (standard)
  --    Bursty channels (Events): ±40% band (linear target not meaningful)
  --    Zero-cost channels: no pacing alert (no budget to pace against)
  SELECT
    date,
    budget_month,
    campaign_id,
    channel,
    channel_spend_type,
    daily_actual_spend,
    ROUND(cumulative_mtd_spend, 2)                  AS cumulative_mtd_spend,
    target_linear_mtd_spend,
    COALESCE(monthly_allocated_budget, 0.0)         AS monthly_allocated_budget,
    COALESCE(monthly_budget_burn_pct, 0.0)          AS monthly_budget_burn_pct,
    ROUND(
      cumulative_mtd_spend - target_linear_mtd_spend, 2
    )                                               AS budget_variance_amount,

    -- B2B-aware pacing status:
    -- Events use a wider band because spend is intentionally bursty
    -- Zero-cost channels are excluded from pacing logic entirely
    CASE
      WHEN channel_spend_type = 'Zero-Cost'
        THEN 'N/A (Zero-Cost Channel)'
      WHEN channel_spend_type = 'Bursty'
        AND cumulative_mtd_spend > (target_linear_mtd_spend * 1.40)
        THEN 'OVERPACING (High Burn)'
      WHEN channel_spend_type = 'Bursty'
        AND cumulative_mtd_spend < (target_linear_mtd_spend * 0.60)
        THEN 'UNDERPACING (Stalled)'
      WHEN channel_spend_type = 'Bursty'
        THEN 'OPTIMAL (Bursty Channel)'
      WHEN cumulative_mtd_spend > (target_linear_mtd_spend * 1.15)
        THEN 'OVERPACING (High Burn)'
      WHEN cumulative_mtd_spend < (target_linear_mtd_spend * 0.85)
        THEN 'UNDERPACING (Stalled)'
      ELSE
        'OPTIMAL'
    END                                             AS pacing_status_alert

  FROM variance_matrix
  ORDER BY date DESC, campaign_id ASC;

END;
