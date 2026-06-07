-- gen_campaign_budgets_dim.sql
-- Generates monthly budget allocations per campaign for the budget pacing model.
-- Simulates realistic B2B SaaS quarterly budget planning behaviour:
--   Q1: moderate budgets (Jan planning, budgets not fully deployed)
--   Q2: increasing budgets (pipeline build ahead of H1 close)
--   Q3: highest budgets (push to hit annual targets)
--   Q4: variable (some companies freeze spend, others accelerate)
--
-- Budget ranges by channel (monthly):
--   LinkedIn Ads  £15,000–£55,000  — highest CPM channel, largest B2B budget
--   Google Ads    £10,000–£40,000  — search intent capture
--   Organic Search £0              — zero-cost channel, no budget needed
--   Email          £0              — zero-cost channel, no budget needed
--   Events         £0–£20,000      — bursty, event-specific allocation
--
-- One row per campaign per month across the full date range.
-- Output: marketing_data.campaign_budgets_dim

CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.campaign_budgets_dim` AS

WITH months AS (
  SELECT
    DATE_TRUNC(month_start, MONTH)                                      AS budget_month,
    EXTRACT(QUARTER FROM month_start)                                   AS quarter,
    EXTRACT(MONTH FROM month_start)                                     AS month_num
  FROM UNNEST(
    GENERATE_DATE_ARRAY('2025-01-01', '2026-05-01', INTERVAL 1 MONTH)
  ) AS month_start
),

campaigns AS (
  SELECT 101 AS campaign_id, 'LinkedIn Ads'    AS channel UNION ALL
  SELECT 102,                 'Google Ads'               UNION ALL
  SELECT 103,                 'Organic Search'           UNION ALL
  SELECT 104,                 'Email'                    UNION ALL
  SELECT 105,                 'Events'
),

-- Cross join months to campaigns to get one row per campaign per month
budget_base AS (
  SELECT
    m.budget_month,
    m.quarter,
    m.month_num,
    c.campaign_id,
    c.channel
  FROM months m
  CROSS JOIN campaigns c
)

SELECT
  budget_month,
  campaign_id,
  channel,

  -- Monthly budget allocation by channel with quarterly scaling
  -- Q3 gets 1.3x multiplier (push to hit annual targets)
  -- Q1 gets 0.8x multiplier (budgets not fully deployed in January)
  CASE
    WHEN channel = 'Organic Search' THEN 0.0
    WHEN channel = 'Email'          THEN 0.0

    WHEN channel = 'LinkedIn Ads' THEN
      ROUND(
        CASE
          WHEN quarter = 1 THEN (15000 + RAND() * 20000) * 0.8
          WHEN quarter = 2 THEN (15000 + RAND() * 25000) * 1.0
          WHEN quarter = 3 THEN (15000 + RAND() * 30000) * 1.3
          WHEN quarter = 4 THEN (15000 + RAND() * 25000) * 1.1
        END, 2
      )

    WHEN channel = 'Google Ads' THEN
      ROUND(
        CASE
          WHEN quarter = 1 THEN (10000 + RAND() * 15000) * 0.8
          WHEN quarter = 2 THEN (10000 + RAND() * 20000) * 1.0
          WHEN quarter = 3 THEN (10000 + RAND() * 25000) * 1.3
          WHEN quarter = 4 THEN (10000 + RAND() * 20000) * 1.1
        END, 2
      )

    WHEN channel = 'Events' THEN
      -- Events budget is sparse — only allocated in certain months
      -- Reflects real event calendar (conferences, webinars, field events)
      CASE
        WHEN month_num IN (3, 6, 9, 11) THEN ROUND(5000 + RAND() * 15000, 2)
        ELSE 0.0
      END

  END                                                                   AS monthly_allocated_budget

FROM budget_base
ORDER BY budget_month, campaign_id;
