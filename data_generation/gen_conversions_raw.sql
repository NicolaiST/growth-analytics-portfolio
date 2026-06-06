-- gen_conversions_raw.sql
-- Generates 10,000 synthetic B2B SaaS conversion events across Jan 2025 – May 2026.
--
-- Conversion funnel design (realistic B2B SaaS split):
--   MQL              35% — Marketing Qualified Leads (content downloads, form fills)
--   Demo Request     30% — High-intent bottom-of-funnel actions
--   Trial Sign-up    25% — Product-led growth self-serve trials
--   Closed Won       10% — Revenue-generating conversions
--
-- Revenue logic:
--   MQL / Demo Request / Trial  → NULL revenue (pre-revenue funnel stages)
--   Closed Won                  → ACV between £500 and £25,000 (B2B deal range)
--
-- type_rand is assigned once and reused for both conversion_type and revenue
-- to ensure logical consistency. See crm_events_raw for same pattern.

CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.conversion_raw` AS

WITH conversion_rows AS (
  SELECT
    row_id,
    RAND() AS type_rand
  FROM UNNEST(GENERATE_ARRAY(1, 10000)) AS row_id
)

SELECT
  row_id                                                                        AS conversion_id,

  DATE_ADD(
    DATE '2025-01-01',
    INTERVAL CAST(FLOOR(RAND() * 420) AS INT64) DAY
  )                                                                             AS conversion_date,

  -- campaign_id 101–105 maps to LinkedIn, Google, Organic, Email, Events
  CAST(FLOOR(101 + RAND() * 5) AS INT64)                                       AS campaign_id,

  -- user_id range allows for repeat converters (realistic for multi-touch B2B funnels)
  CONCAT('USR-', CAST(FLOOR(100000 + RAND() * 900000) AS INT64))              AS user_id,

  -- B2B SaaS funnel stages using stable type_rand
  CASE
    WHEN type_rand < 0.35 THEN 'MQL'
    WHEN type_rand < 0.65 THEN 'Demo Request'
    WHEN type_rand < 0.90 THEN 'Trial Sign-up'
    ELSE                       'Closed Won'
  END                                                                           AS conversion_type,

  -- Revenue only at Closed Won stage — B2B ACV range £500–£25,500
  -- Same type_rand threshold ensures no mismatch between type and revenue
  CASE
    WHEN type_rand < 0.90 THEN NULL
    ELSE                       ROUND(500 + RAND() * 25000, 2)
  END                                                                           AS revenue

FROM conversion_rows
ORDER BY conversion_date;
