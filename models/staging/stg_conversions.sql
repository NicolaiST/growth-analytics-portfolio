-- stg_conversions.sql
-- Source: marketing_data.conversion_raw
-- Reads the raw conversion generator output, casts types,
-- and enforces consistent null handling for downstream models.
--
-- Design notes:
--   - Lead Sign-up revenue is NULL by design in the source generator
--     (type_rand < 0.40 produces NULL revenue). COALESCE'd to 0.0 here
--     for safe aggregation in mart models.
--   - Purchase revenue is always populated in the source (type_rand >= 0.40).
--     No data quality workaround needed — generator ensures consistency.
--   - user_id duplicates are intentional: a single user can convert multiple
--     times across the 420-day window, enabling cohort and LTV analysis.
--   - campaign_id range 101–105 maps to dim_campaigns for channel enrichment.

SELECT
  CAST(conversion_id AS INT64)                    AS conversion_id,
  CAST(conversion_date AS DATE)                   AS conversion_date,
  CAST(campaign_id AS INT64)                      AS campaign_id,
  CAST(user_id AS STRING)                         AS user_id,
  CAST(conversion_type AS STRING)                 AS conversion_type,
  COALESCE(
    CAST(revenue AS FLOAT64), 0.0
  )                                               AS revenue,
  -- Derived: useful flag for downstream filtering without string matching
  CASE
    WHEN conversion_type = 'Purchase' THEN TRUE
    ELSE FALSE
  END                                             AS is_purchase

FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
WHERE conversion_date IS NOT NULL
  AND conversion_id IS NOT NULL
ORDER BY conversion_date
