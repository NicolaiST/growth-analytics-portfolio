# Growth Analytics Portfolio — BigQuery Data Models


End-to-end B2B SaaS marketing analytics data model built in BigQuery Sandbox.
Covers budget pacing, multi-channel attribution, cohort LTV, a Marketing Mix
Model with geometric adstock decay, and revenue prediction using BigQuery ML.


**Stack:** BigQuery · SQL · BigQuery ML · Looker Studio
**Live Dashboard:** [Business Performance Dashboard](https://datastudio.google.com/reporting/a78c9cee-b49d-4919-9505-b290a33205dd)
**GitHub:** github.com/NicolaiST/growth-analytics-portfolio


## Architecture


Data Generators → Raw Tables → Staging → Marts → ML Models → Looker Studio


| Layer      | Folder             | Purpose                               |
|------------|--------------------|---------------------------------------|
| Generators | /data_generation   | Synthetic B2B data with real quality  |
| Raw        | marketing_data     | Generated source tables               |
| Raw        | crm_data           | CRM lifecycle events                  |
| Staging    | models/staging     | Cleaned, typed, null-handled          |
| Dimensions | models/dimensions  | Campaign, channel reference tables    |
| Marts      | models/marts       | Modelled analytical facts             |
| ML         | models/ml          | BigQuery ML prediction models         |
| Reporting  | analytics_reporting| Looker Studio data sources            |


## Key Models


### 1. Marketing Mix Model with Adstock Decay
**File:** models/marts/fct_marketing_mmm_features.sql
Geometric adstock decay across B2B channels. LinkedIn uses a 0.70 decay
rate (longer enterprise decision cycles); Google Ads uses 0.60 (strong
intent but moderate carryover). Output feeds the revenue prediction model.


### 2. Revenue Prediction Model (BigQuery ML)
**File:** models/ml/revenue_prediction_model.sql
Linear regression using adstock-adjusted spend features and seasonality
signals. Trained on fct_marketing_mmm_features with sequential 80/20 split.


### 3. Cohort LTV Matrix
**File:** models/marts/fct_cohort_ltv_matrix.sql
Cumulative per-user LTV and retention rate by acquisition cohort and channel.
Tracks both broad activity LTV and closed-won-only LTV separately —
critical distinction in B2B where most cohort activity is pre-revenue.


### 4. Budget Pacing
**File:** models/marts/fct_marketing_budget_pacing.sql
B2B-aware daily budget pacing with tiered variance thresholds:
±15% for paid channels, ±40% for bursty channels (Events), N/A for
zero-cost channels (Organic, Email).


### 5. Core Marketing Performance
**File:** models/marts/fct_marketing_performance.sql
Central B2B fact table joining spend + engagement to funnel conversion
stages (MQL, Demo, Trial, Closed Won). Computes CAC, ROAS, cost_per_mql,
cost_per_demo, and 7-day rolling spend at campaign/channel/day granularity.


### 6. B2B Synthetic Data Generators
**Folder:** /data_generation
Synthetic data designed to mirror real B2B SaaS data quality — including
intentional nulls (zero-cost channels), bursty spend patterns (Events),
and a realistic B2B conversion funnel (MQL → Demo → Trial → Closed Won).


## What I'd Add With More Time


### Multi-Touch Attribution (In Progress — ETA 2 weeks)
Last-touch attribution understates the contribution of awareness channels
(LinkedIn, Organic) in long B2B sales cycles. Planning to build:
- gen_event_touchpoints_raw.sql — user journey touchpoint generator
- fct_attribution_linear.sql — equal credit across all touchpoints
- fct_attribution_position.sql — 40/20/40 U-shaped model
- fct_attribution_comparison.sql — side-by-side model comparison


### Production Enhancements
- dbt: migrate stored procedures to dbt models with schema tests
- Python: hill saturation curves for MMM diminishing returns
- Account-based attribution: group touchpoints by company domain
- Scheduled queries replacing manual stored procedure execution
