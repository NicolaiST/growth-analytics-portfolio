-- gen_crm_events_raw.sql
-- Generates 4,500 synthetic B2B SaaS CRM lifecycle events across Jan 2025 – Jun 2026.
--
-- Design decisions:
--   Simulates post-acquisition customer health events — what happens to a customer
--   after they close. Each row represents a status change event for a user,
--   reflecting how a real B2B CRM (HubSpot, Salesforce) would track account health.
--
-- Customer status distribution:
--   Active    50% — paying customers in good standing
--   At Risk   20% — showing signs of churn (low engagement, support tickets)
--   Expanded  15% — upsell or seat expansion event
--   Churned   15% — contract cancelled
--
-- MRR design:
--   Active and Expanded customers carry MRR (£500–£5,000/month — realistic B2B range)
--   At Risk customers carry MRR (still paying but flagged)
--   Churned customers have NULL MRR (no longer generating revenue)
--
-- Technical note:
--   status_rand is assigned once as a stable variable and reused across both
--   the customer_status and monthly_recurring_revenue CASE statements.
--   This ensures logical consistency between the two fields — a known pattern
--   for avoiding non-deterministic RAND() behaviour in BigQuery CTEs where
--   calling RAND() twice produces two independent values.
--
-- Date range: Jan 2025 – Jun 2026 (505 days)
-- Row count: 4,500 events
-- Output: marketing_data.crm_events_raw

CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.crm_events_raw` AS

WITH row_generator AS (
  SELECT * FROM UNNEST(GENERATE_ARRAY(1, 4500)) AS row_id
),

random_assigned AS (
  SELECT
    CONCAT('USR-', CAST(FLOOR(100000 + RAND() * 900000) AS INT64))        AS user_id,
    DATE_ADD(
      DATE '2025-01-01',
      INTERVAL CAST(FLOOR(RAND() * 505) AS INT64) DAY
    )                                                                       AS status_change_date,
    -- Stable random variables assigned once and reused below
    -- Prevents non-deterministic RAND() behaviour across CASE statements
    RAND()                                                                  AS status_rand,
    RAND()                                                                  AS revenue_rand
  FROM row_generator
)

SELECT
  user_id,
  status_change_date,

  -- Customer status: reflects B2B CRM account health states
  -- Uses stable status_rand to ensure MRR is always consistent with status
  CASE
    WHEN status_rand < 0.15 THEN 'Churned'
    WHEN status_rand < 0.30 THEN 'Expanded'
    WHEN status_rand < 0.50 THEN 'At Risk'
    ELSE                         'Active'
  END                                                                       AS customer_status,

  -- MRR: NULL for Churned only — Active, At Risk, and Expanded all carry revenue
  -- Range £500–£5,000/month reflects realistic B2B SaaS contract values
  -- Uses same status_rand threshold to guarantee status/MRR consistency
  CASE
    WHEN status_rand < 0.15 THEN NULL
    ELSE CAST(FLOOR(500 + revenue_rand * 4500) AS INT64)
  END                                                                       AS monthly_recurring_revenue

FROM random_assigned;
