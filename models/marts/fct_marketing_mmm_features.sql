-- fct_marketing_mmm_features.sql
-- Marketing Mix Model (MMM) feature engineering table.
-- Transforms daily channel spend and impressions into adstock-adjusted
-- features for use as inputs to the revenue_prediction_model.
--
-- MMM Methodology:
--   This model implements geometric adstock decay to capture the carryover
--   effect of paid media spend — the idea that advertising spend on day N
--   continues to influence conversions on days N+1, N+2, etc.
--
--   Adstock formula: adstock(t) = spend(t) + λ·spend(t-1) + λ²·spend(t-2)
--   where λ is the decay rate (channel-specific, calibrated below).
--
-- Decay rates used:
--   Google Ads  λ = 0.70  — Search intent has longer carryover; users may
--                           click an ad today but convert after further research.
--   Meta Ads    λ = 0.50  — Social ads decay faster; impression-driven behaviour
--                           is more immediate and less intent-driven.
--
-- Known limitations (production enhancements flagged):
--   1. ADSTOCK WINDOW: Currently 3 days (t, t-1, t-2). Real MMM typically uses
--      4–8 weeks of carryover. Extending the window requires more LAG() calls
--      or a recursive CTE approach. Decay rates would also need empirical
--      calibration on real conversion data rather than assumed values.
--
--   2. SATURATION (HILL FUNCTION): This model captures decay but not diminishing
--      returns — the effect where doubling spend does not double conversions.
--      A production MMM would apply a Hill transformation:
--        saturation(spend) = spend^α / (spend^α + K^α)
--      where α controls curve shape and K is the half-saturation point.
--      This is best implemented in Python (e.g. via PyMC-Marketing or
--      Meta's Robyn library) rather than SQL.
--
--   3. ORGANIC / EMAIL SPEND: Currently set to 0.0 by design (zero-cost channels).
--      In a production model, organic search would use a proxy variable
--      (e.g. impressions or ranking position) rather than spend = 0,
--      as 0 spend suppresses its adstock signal entirely.
--
-- Source table: fct_marketing_performance (mart layer)
-- Output: fct_marketing_mmm_features (mart layer)
-- Downstream: revenue_prediction_model (BigQuery ML)

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_mmm_prep`()
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_marketing_mmm_features` AS

  -- 1. Pivot daily spend and impressions into one row per date
  --    Source uses COALESCE'd spend from staging, so no nulls expected here.
  --    Organic Search and Email spend will be 0.0 by design.
  WITH daily_channel_pivot AS (
    SELECT
      date,

      -- Spend by channel
      SUM(CASE WHEN channel = 'LinkedIn Ads'    THEN spend ELSE 0.0 END) AS spend_linkedin,
      SUM(CASE WHEN channel = 'Google Ads'      THEN spend ELSE 0.0 END) AS spend_google,
      SUM(CASE WHEN channel = 'Organic Search'  THEN spend ELSE 0.0 END) AS spend_organic,
      SUM(CASE WHEN channel LIKE 'Email%'       THEN spend ELSE 0.0 END) AS spend_email,
      SUM(CASE WHEN channel = 'Events'          THEN spend ELSE 0.0 END) AS spend_events,

       -- Impressions by channel
      SUM(CASE WHEN channel = 'LinkedIn Ads'    THEN impressions ELSE 0 END) AS impressions_linkedin,
      SUM(CASE WHEN channel = 'Google Ads'      THEN impressions ELSE 0 END) AS impressions_google,
      SUM(CASE WHEN channel = 'Organic Search'  THEN impressions ELSE 0 END) AS impressions_organic,
      SUM(CASE WHEN channel LIKE 'Email%'       THEN impressions ELSE 0 END) AS impressions_email,
      SUM(CASE WHEN channel = 'Events'          THEN impressions ELSE 0 END) AS impressions_events,
  

      -- Target variable: total attributed revenue across all channels
      -- Attribution-independent — used as the label in the ML model
      SUM(attributed_revenue)                                               AS total_revenue

    FROM `growth-dashboard-portfolio.marketing_data.fct_marketing_performance`
    GROUP BY 1
  ),

  -- 2. Apply geometric adstock decay to paid media channels only
  --    Free channels (Organic, Email, Affiliate) have no spend signal to decay.
  --    Window: 3 days (current + 2 lags). See header note on window limitation.
  adstock_calculations AS (
    SELECT
      *,

  -- LinkedIn Ads adstock (λ = 0.70)
      -- B2B social ads have longer carryover than B2C — decision cycles are longer
      ROUND(
        spend_linkedin
        + (0.70 * LAG(spend_linkedin, 1, 0.0) OVER (ORDER BY date))
        + (0.49 * LAG(spend_linkedin, 2, 0.0) OVER (ORDER BY date)),
        2
      ) AS adstock_spend_linkedin,

      -- Google Ads adstock (λ = 0.60)
      -- Search intent is strong but B2B purchase cycles mean moderate carryover
      ROUND(
        spend_google
        + (0.60 * LAG(spend_google, 1, 0.0) OVER (ORDER BY date))
        + (0.36 * LAG(spend_google, 2, 0.0) OVER (ORDER BY date)),
        2
      ) AS adstock_spend_google

    FROM daily_channel_pivot
  )

  -- 3. Final output ordered for readability
  --    Note: stored procedure pattern used for manual execution in BigQuery Sandbox.
  --    Production equivalent: scheduled query or dbt model with defined run cadence.
  SELECT *
  FROM adstock_calculations
  ORDER BY date DESC;

END;
