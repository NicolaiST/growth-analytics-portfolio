# Growth Analytics Portfolio — BigQuery Data Models


End-to-end marketing analytics data model built in BigQuery Sandbox, covering budget pacing, multi-channel attribution, cohort LTV analysis, a Marketing Mix Model with geometric adstock decay, and revenue prediction using BigQuery ML.

**Stack:** BigQuery · SQL · BigQuery ML · Looker Studio
**Live Dashboard:** [Business Performance Dashboard] - https://datastudio.google.com/reporting/a78c9cee-b49d-4919-9505-b290a33205dd

## Architecture


Raw Sources → Staging Models → Fact Tables → ML Models → Looker Studio


Data Generators → Raw Tables → Staging → Marts → ML → Reporting


| Layer      | Folder              | Purpose                               |
|------------|---------------------|---------------------------------------|
| Generators | /data_generation    | Synthetic data with realistic quality |
| Raw        | marketing_data      | Generated source tables               |
| Raw        | crm_data            | CRM events and conversions            |
| Staging    | models/staging      | Cleaned + typed + null-handled        |
| Marts      | fct_* tables        | Modelled analytical facts             |
| ML         | *_model             | BigQuery ML predictions               |
| Reporting  | analytics_reporting | Looker Studio data sources            |


## Key Models


### 1. Marketing Mix Model with Adstock Decay
**File:** models/marts/fct_marketing_mmm_features.sql
Implements geometric adstock decay to model the carryover effect of
paid media spend. Google Ads uses a 70% decay rate (longer search
intent carryover); Meta uses 50% (faster social decay). Built as
feature inputs for the revenue prediction model.


### 2. Revenue Prediction Model
**File:** models/ml/revenue_prediction_model.sql
BigQuery ML linear regression using adstock-adjusted spend features
and time seasonality signals to forecast revenue from planned spend.


### 3. Cohort LTV Matrix
**File:** models/marts/fct_cohort_ltv_matrix.sql
Calculates cumulative per-user LTV and retention rate by acquisition
cohort and channel, using window functions to build the full LTV curve
over time rather than a single static figure.


### 4. Budget Pacing
**File:** models/marts/fct_marketing_budget_pacing.sql
Daily budget pacing model with linear run-rate targets and a 15%
variance threshold that flags campaigns as OPTIMAL / OVERPACING /
UNDERPACING using CASE logic.
