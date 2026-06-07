-- cac_spend_predictor.sql
-- BigQuery ML model to predict Customer Acquisition Cost (CAC)
-- from channel spend inputs using adstock-adjusted features.
--
-- Commercial purpose:
--   Answers the question "how much will it cost to acquire each customer
--   at this spend level?" — enabling budget allocation decisions based on
--   predicted efficiency rather than historical averages alone.
--
-- Relationship to revenue_prediction_model:
--   These two ML models work as a pair:
--   revenue_prediction_model → "how much revenue will this spend generate?"
--   cac_spend_predictor      → "how much will each acquired customer cost?"
--   Together they enable spend scenarios that optimise for both growth
--   and acquisition efficiency simultaneously.
--
-- B2B context:
--   CAC in B2B is highly variable by channel and season:
--   - LinkedIn typically produces higher CAC than Google due to CPM costs
--     but also acquires higher ACV customers (not captured in this model)
--   - Q4 typically shows higher CAC as competitors increase spend
--   - Events spend is bursty and produces unpredictable CAC per event
--   This model captures spend-to-CAC patterns across channels so budget
--   allocation decisions can be made on predicted efficiency.
--
-- Feature inputs:
--   adstock_spend_linkedin  — carryover-adjusted LinkedIn spend (MMM model)
--   adstock_spend_google    — carryover-adjusted Google spend (MMM model)
--   spend_email             — email spend (zero-cost, acts as baseline control)
--   spend_events            — events/webinar spend (bursty pattern)
--   day_of_week             — captures weekday/weekend delivery differences
--   month_of_year           — captures seasonal CAC variation
--   quarter                 — B2B budgets shift significantly by quarter
--
-- Target variable: cac (spend / closed_won_count)
--   Source: fct_marketing_performance.cac
--   NULL rows excluded — zero-cost channels and days with no closed won events
--   is_paid_channel = TRUE filter ensures training on media-driven CAC only
--   CAC outlier filter (> 50000) removes single large deals on low-spend days
--   that would skew the regression line
--
-- Train/eval split: sequential 80/20
--   Sequential split is correct for time-series spend data — random split
--   would leak future spend patterns into training, producing optimistic results
--
-- enable_global_explain = TRUE:
--   Enables ML.GLOBAL_EXPLAIN() after training to show feature importance.
--   Run after training:
--   SELECT * FROM ML.GLOBAL_EXPLAIN(
--     MODEL `growth-dashboard-portfolio.marketing_data.cac_spend_predictor`
--   )
--   This returns which spend inputs drive CAC most strongly —
--   a compelling output to include in portfolio documentation.
--
-- Sources:
--   marketing_data.fct_marketing_mmm_features  — adstock spend features
--   marketing_data.fct_marketing_performance   — CAC + channel classification
-- Output: marketing_data.cac_spend_predictor (BigQuery ML model)

CREATE OR REPLACE MODEL
  `growth-dashboard-portfolio.marketing_data.cac_spend_predictor`
OPTIONS(
  model_type               = 'linear_reg',
  input_label_cols         = ['cac'],
  data_split_method        = 'seq',
  data_split_col           = 'split_date',
  data_split_eval_fraction = 0.2,
  enable_global_explain    = TRUE
) AS

SELECT
  mmm.adstock_spend_linkedin,
  mmm.adstock_spend_google,
  mmm.spend_email,
  mmm.spend_events,
  EXTRACT(DAYOFWEEK FROM mmm.date) AS day_of_week,
  EXTRACT(MONTH    FROM mmm.date)  AS month_of_year,
  EXTRACT(QUARTER  FROM mmm.date)  AS quarter,
  -- split_date used for sequential ordering only — not a model feature
  -- BigQuery ML uses this to split train/eval chronologically
  UNIX_DATE(mmm.date) AS split_date,
  fmp.cac

FROM `growth-dashboard-portfolio.marketing_data.fct_marketing_mmm_features` mmm
INNER JOIN `growth-dashboard-portfolio.marketing_data.fct_marketing_performance` fmp
  ON  mmm.date        = fmp.date

WHERE
  fmp.is_paid_channel = TRUE
  AND fmp.cac IS NOT NULL
  AND fmp.cac < 50000;
