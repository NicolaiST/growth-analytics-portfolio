-- sp_analytics_mmm_prep.sql
-- Stored procedure wrapper for fct_marketing_mmm_features.
-- Pivots daily channel spend and impressions into one row per date
-- and applies geometric adstock decay to paid media channels.
--
-- Execute: CALL `growth-dashboard-portfolio.marketing_data.sp_analytics_mmm_prep`();
--
-- Output table: marketing_data.fct_marketing_mmm_features
-- Run after: sp_transform_marketing_data (depends on fct_marketing_performance)
-- Run before: revenue_prediction_model, cac_spend_predictor (both depend on this table)
--
-- Adstock decay rates:
--   LinkedIn Ads λ=0.70 — longer B2B enterprise decision cycles
--   Google Ads   λ=0.60 — strong search intent, moderate carryover
--
-- Known limitations:
--   1. Window size is 3 days (t, t-1, t-2). Production MMM uses 4-8 weeks.
--   2. No hill saturation function — diminishing returns not modelled.
--      Production implementation would use Python (PyMC-Marketing or Robyn).

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_mmm_prep`()
OPTIONS(strict_mode=false)
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_mmm_features` AS

  WITH daily_channel_pivot AS (
    SELECT
      date,
      SUM(CASE WHEN channel = 'LinkedIn Ads'   THEN spend ELSE 0.0 END)  AS spend_linkedin,
      SUM(CASE WHEN channel = 'Google Ads'     THEN spend ELSE 0.0 END)  AS spend_google,
      SUM(CASE WHEN channel = 'Organic Search' THEN spend ELSE 0.0 END)  AS spend_organic,
      SUM(CASE WHEN channel LIKE 'Email%'      THEN spend ELSE 0.0 END)  AS spend_email,
      SUM(CASE WHEN channel = 'Events'         THEN spend ELSE 0.0 END)  AS spend_events,
      SUM(CASE WHEN channel = 'LinkedIn Ads'   THEN impressions ELSE 0 END) AS impressions_linkedin,
      SUM(CASE WHEN channel = 'Google Ads'     THEN impressions ELSE 0 END) AS impressions_google,
      SUM(CASE WHEN channel = 'Organic Search' THEN impressions ELSE 0 END) AS impressions_organic,
      SUM(CASE WHEN channel LIKE 'Email%'      THEN impressions ELSE 0 END) AS impressions_email,
      SUM(CASE WHEN channel = 'Events'         THEN impressions ELSE 0 END) AS impressions_events,
      SUM(attributed_revenue)                                               AS total_revenue
    FROM `growth-dashboard-portfolio.marketing_data.fct_marketing_performance`
    GROUP BY 1
  ),

  adstock_calculations AS (
    SELECT
      *,
      -- LinkedIn Ads adstock (λ=0.70)
      -- Day 0: 1.00 | Day -1: 0.70 | Day -2: 0.49
      ROUND(
        spend_linkedin
        + (0.70 * LAG(spend_linkedin, 1, 0.0) OVER (ORDER BY date))
        + (0.49 * LAG(spend_linkedin, 2, 0.0) OVER (ORDER BY date)),
        2
      )                                                                    AS adstock_spend_linkedin,

      -- Google Ads adstock (λ=0.60)
      -- Day 0: 1.00 | Day -1: 0.60 | Day -2: 0.36
      ROUND(
        spend_google
        + (0.60 * LAG(spend_google, 1, 0.0) OVER (ORDER BY date))
        + (0.36 * LAG(spend_google, 2, 0.0) OVER (ORDER BY date)),
        2
      )                                                                    AS adstock_spend_google

    FROM daily_channel_pivot
  )

  SELECT *
  FROM adstock_calculations
  ORDER BY date DESC;

END;
