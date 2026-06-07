-- sp_analytics_cohort_ltv.sql
-- Stored procedure wrapper for fct_cohort_ltv_matrix.
-- Calculates cumulative LTV, retention rate, and closed-won revenue
-- by acquisition cohort, channel, and cohort age month.
--
-- Execute: CALL `growth-dashboard-portfolio.marketing_data.sp_analytics_cohort_ltv`();
--
-- Output table: marketing_data.fct_cohort_ltv_matrix
-- Run after: gen_conversions_raw, dim_campaigns
--
-- B2B context:
--   Most cohort activity is pre-revenue (MQL, Demo, Trial).
--   Two LTV metrics are tracked separately:
--   cumulative_per_user_ltv      — all activity including pre-revenue
--   cumulative_closed_won_ltv    — revenue-generating events only
--
-- Known limitations:
--   Retention defined as any conversion event in the period — broad proxy.
--   Production would use product login events or CRM stage progression.

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_cohort_ltv`()
OPTIONS(strict_mode=false)
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_cohort_ltv_matrix` AS

  WITH user_acquisition AS (
    SELECT
      user_id,
      MIN(conversion_date)                                                  AS acquisition_date,
      DATE_TRUNC(MIN(conversion_date), MONTH)                               AS acquisition_cohort_month,
      ARRAY_AGG(campaign_id      ORDER BY conversion_date ASC LIMIT 1)[OFFSET(0)] AS acquisition_campaign_id,
      ARRAY_AGG(conversion_type  ORDER BY conversion_date ASC LIMIT 1)[OFFSET(0)] AS acquisition_conversion_type
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
    GROUP BY user_id
  ),

  transaction_lifecycle AS (
    SELECT
      c.user_id,
      ua.acquisition_cohort_month,
      ua.acquisition_campaign_id,
      ua.acquisition_conversion_type,
      c.conversion_date,
      c.conversion_type,
      COALESCE(c.revenue, 0.0)                                              AS revenue,
      DATE_DIFF(
        DATE_TRUNC(c.conversion_date, MONTH),
        ua.acquisition_cohort_month,
        MONTH
      )                                                                     AS cohort_age_month
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw` c
    INNER JOIN user_acquisition ua ON c.user_id = ua.user_id
  ),

  cohort_sizes AS (
    SELECT
      acquisition_cohort_month,
      acquisition_campaign_id,
      COUNT(DISTINCT user_id)                                               AS total_cohort_users
    FROM user_acquisition
    GROUP BY 1, 2
  ),

  cohort_revenue_steps AS (
    SELECT
      acquisition_cohort_month,
      acquisition_campaign_id,
      cohort_age_month,
      COUNT(DISTINCT user_id)                                               AS active_users_in_period,
      SUM(revenue)                                                          AS period_revenue,
      SUM(CASE WHEN conversion_type = 'Closed Won' THEN revenue ELSE 0.0 END) AS period_closed_won_revenue,
      COUNT(CASE WHEN conversion_type = 'Closed Won' THEN 1 END)           AS period_closed_won_count
    FROM transaction_lifecycle
    GROUP BY 1, 2, 3
  )

  SELECT
    r.acquisition_cohort_month,
    dc.channel                                                              AS acquisition_channel,
    r.cohort_age_month,
    s.total_cohort_users,
    r.active_users_in_period,
    ROUND(
      SAFE_DIVIDE(r.active_users_in_period, s.total_cohort_users) * 100, 2
    )                                                                       AS retention_rate_pct,
    ROUND(r.period_revenue, 2)                                              AS gross_period_revenue,
    ROUND(r.period_closed_won_revenue, 2)                                   AS period_closed_won_revenue,
    r.period_closed_won_count,
    ROUND(SUM(r.period_revenue) OVER (
      PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
      ORDER BY r.cohort_age_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                                                   AS cumulative_cohort_revenue,
    ROUND(SAFE_DIVIDE(
      SUM(r.period_revenue) OVER (
        PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
        ORDER BY r.cohort_age_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ), s.total_cohort_users
    ), 2)                                                                   AS cumulative_per_user_ltv,
    ROUND(SAFE_DIVIDE(
      SUM(r.period_closed_won_revenue) OVER (
        PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
        ORDER BY r.cohort_age_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ), s.total_cohort_users
    ), 2)                                                                   AS cumulative_closed_won_ltv_per_user

  FROM cohort_revenue_steps r
  LEFT JOIN cohort_sizes s
    ON  r.acquisition_cohort_month = s.acquisition_cohort_month
    AND r.acquisition_campaign_id  = s.acquisition_campaign_id
  LEFT JOIN `growth-dashboard-portfolio.marketing_data.dim_campaigns` dc
    ON r.acquisition_campaign_id = dc.campaign_id
  ORDER BY acquisition_cohort_month ASC, cohort_age_month ASC;

END;
