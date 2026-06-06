-- stg_conversions.sql
-- Source: marketing_data.conversion_raw
-- Cleans and types the B2B conversion funnel data.
-- Adds derived fields for easier downstream filtering.
--
-- Funnel stage reference:
--   MQL           → top of funnel, no revenue
--   Demo Request  → bottom of funnel, high intent, no revenue
--   Trial Sign-up → PLG motion, no immediate revenue
--   Closed Won    → revenue event, ACV £500–£25,500

SELECT
  CAST(conversion_id AS INT64)                    AS conversion_id,
  CAST(conversion_date AS DATE)                   AS conversion_date,
  CAST(campaign_id AS INT64)                      AS campaign_id,
  CAST(user_id AS STRING)                         AS user_id,
  CAST(conversion_type AS STRING)                 AS conversion_type,

  -- Revenue is NULL for all pre-revenue funnel stages — COALESCE to 0 for aggregation
  COALESCE(CAST(revenue AS FLOAT64), 0.0)         AS revenue,

  -- Derived: TRUE only at the revenue stage
  CASE
    WHEN conversion_type = 'Closed Won' THEN TRUE
    ELSE FALSE
  END                                             AS is_closed_won,

  -- Derived: funnel stage number for ordering and bucketing
  CASE
    WHEN conversion_type = 'MQL'           THEN 1
    WHEN conversion_type = 'Demo Request'  THEN 2
    WHEN conversion_type = 'Trial Sign-up' THEN 3
    WHEN conversion_type = 'Closed Won'    THEN 4
    ELSE NULL
  END                                             AS funnel_stage_order

FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
WHERE conversion_date IS NOT NULL
  AND conversion_id IS NOT NULL
ORDER BY conversion_date;
