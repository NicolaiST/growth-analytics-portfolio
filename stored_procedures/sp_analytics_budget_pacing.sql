-- sp_analytics_budget_pacing.sql
-- Stored procedure wrapper for fct_marketing_budget_pacing.
-- Tracks cumulative spend against a linear run-rate target and flags
-- campaigns that deviate beyond acceptable thresholds.
--
-- Execute: CALL `growth-dashboard-portfolio.marketing_data.sp_analytics_budget_pacing`();
--
-- Output table: marketing_data.fct_marketing_budget_pacing
-- Run after: gen_marketing_perf_raw, gen_campaign_budgets_dim
--
-- B2B pacing thresholds:
--   Paid channels (LinkedIn, Google): ±15% variance band
--   Bursty channels (Events):         ±40% variance band
--   Zero-cost channels (Organic, Email): N/A — excluded from pacing logic
--
-- Known limitations:
--   Linear run-rate target assumes even daily spend. Production would use
--   a weighted target based on historical day-of-week spend patterns.
--   Events channel will show frequent UNDERPACING on non-event days by design.

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_budget_pacing`()
OPTIONS(strict_mode=false)
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_budget_pacing` AS

  WITH daily_spend AS (
    SELECT
      date,
      DATE_TRUNC(date, MONTH)                                               AS budget_month,
      campaign_id,
      channel,
      SUM(COALESCE(spend, 0.0))                                             AS daily_actual_spend
    FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
    GROUP BY 1, 2, 3, 4
  ),

  pacing_calculations AS (
    SELECT
      ds.date,
      ds.budget_month,
      ds.campaign_id,
      ds.channel,
      ds.daily_actual_spend,
      SUM(ds.daily_actual_spend) OVER (
        PARTITION BY ds.campaign_id, ds.budget_month
        ORDER BY ds.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )                                                                     AS cumulative_mtd_spend,
      EXTRACT(DAY FROM ds.date)                                             AS day_of_month,
      EXTRACT(DAY FROM LAST_DAY(ds.date))                                   AS total_days_in_month,
      b.monthly_allocated_budget,
      CASE
        WHEN ds.channel IN ('Organic Search', 'Email') THEN 'Zero-Cost'
        WHEN ds.channel = 'Events'                     THEN 'Bursty'
        ELSE                                                'Paid'
      END                                                                   AS channel_spend_type
    FROM daily_spend ds
    LEFT JOIN `growth-dashboard-portfolio.marketing_data.campaign_budgets_dim` b
      ON ds.campaign_id = b.campaign_id
  ),

  variance_matrix AS (
    SELECT
      *,
      ROUND(
        (COALESCE(monthly_allocated_budget, 0.0) / NULLIF(total_days_in_month, 0))
        * day_of_month, 2
      )                                                                     AS target_linear_mtd_spend,
      ROUND(
        (cumulative_mtd_spend / NULLIF(monthly_allocated_budget, 0.0)) * 100, 2
      )                                                                     AS monthly_budget_burn_pct
    FROM pacing_calculations
  )

  SELECT
    date,
    budget_month,
    campaign_id,
    channel,
    channel_spend_type,
    daily_actual_spend,
    ROUND(cumulative_mtd_spend, 2)                                          AS cumulative_mtd_spend,
    target_linear_mtd_spend,
    COALESCE(monthly_allocated_budget, 0.0)                                 AS monthly_allocated_budget,
    COALESCE(monthly_budget_burn_pct, 0.0)                                  AS monthly_budget_burn_pct,
    ROUND(cumulative_mtd_spend - target_linear_mtd_spend, 2)               AS budget_variance_amount,
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
      ELSE 'OPTIMAL'
    END                                                                     AS pacing_status_alert

  FROM variance_matrix
  ORDER BY date DESC, campaign_id ASC;

END;
