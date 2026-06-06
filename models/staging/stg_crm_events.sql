-- stg_crm_events.sql
-- Source: marketing_data.crm_events_raw
-- Reads CRM lifecycle events, casts types, handles MRR nulls
-- for free tier users, and adds a derived is_paying_customer flag.
--
-- Design note: The source generator correctly uses a stable RAND()
-- variable (status_rand) assigned once and reused across both the
-- customer_status and monthly_recurring_revenue CASE statements.
-- This ensures the two fields are always logically consistent —
-- a known pattern for avoiding non-deterministic RAND() behaviour
-- in BigQuery CTEs.

SELECT
  CAST(user_id AS STRING)                         AS user_id,
  CAST(status_change_date AS DATE)                AS status_change_date,
  CAST(customer_status AS STRING)                 AS customer_status,
  -- Free Tier users have NULL MRR by design — COALESCE to 0 for aggregation
  COALESCE(
    CAST(monthly_recurring_revenue AS FLOAT64), 0.0
  )                                               AS monthly_recurring_revenue,
  -- Derived field: TRUE for any paying customer (Upgraded or Churned with MRR history)
  CASE
    WHEN customer_status = 'Active Free Tier' THEN FALSE
    ELSE TRUE
  END                                             AS is_paying_customer,
  -- Derived field: segment for easier downstream filtering
  CASE
    WHEN customer_status = 'Churned'             THEN 'Lost'
    WHEN customer_status = 'Upgraded to Premium' THEN 'Expansion'
    WHEN customer_status = 'Active Free Tier'    THEN 'Free'
    ELSE 'Unknown'
  END                                             AS customer_segment

FROM `growth-dashboard-portfolio.marketing_data.crm_events_raw`
WHERE status_change_date IS NOT NULL
  AND user_id IS NOT NULL
