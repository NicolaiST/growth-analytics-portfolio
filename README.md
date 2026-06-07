# Growth Analytics Portfolio — BigQuery Data Models

End-to-end B2B SaaS marketing analytics data model built in BigQuery Sandbox.
Covers budget pacing, multi-channel attribution, cohort LTV analysis, a Marketing
Mix Model with geometric adstock decay, revenue prediction, and CAC prediction
using BigQuery ML.

**Stack:** BigQuery · SQL · BigQuery ML · Looker Studio  
**Live Dashboard:** [Business Performance Dashboard](https://datastudio.google.com/reporting/a78c9cee-b49d-4919-9505-b290a33205dd)  
**GitHub:** github.com/NicolaiST/growth-analytics-portfolio

---

## Architecture

```
Data Generators → Raw Tables → Staging → Dimensions → Marts → ML Models → Looker Studio
```

| Layer      | Folder              | Purpose                                    |
|------------|---------------------|--------------------------------------------|
| Generators | /data_generation    | Synthetic B2B data with realistic quality  |
| Raw        | marketing_data      | Generated source tables                    |
| Raw        | crm_data            | CRM lifecycle events                       |
| Staging    | models/staging      | Cleaned, typed, null-handled               |
| Dimensions | models/dimensions   | Campaign and channel reference tables      |
| Marts      | models/marts        | Modelled analytical facts                  |
| ML         | models/ml           | BigQuery ML prediction models              |
| Reporting  | analytics_reporting | Looker Studio data sources                 |

---

## Key Models

### 1. Marketing Mix Model with Adstock Decay
**File:** `models/marts/fct_marketing_mmm_features.sql`  
Implements geometric adstock decay to capture the carryover effect of paid media
spend across B2B channels. LinkedIn uses a 0.70 decay rate (longer enterprise
decision cycles); Google Ads uses 0.60 (strong intent, moderate carryover).
Output feeds directly into the revenue prediction model.

### 2. Revenue Prediction Model
**File:** `models/ml/revenue_prediction_model.sql`  
BigQuery ML linear regression using adstock-adjusted spend features and
time seasonality signals to forecast revenue from planned spend.
Sequential 80/20 train/eval split prevents data leakage from future periods.

### 3. CAC Prediction Model
**File:** `models/ml/cac_spend_predictor.sql`  
BigQuery ML linear regression predicting Customer Acquisition Cost from
channel spend inputs. Trained on adstock-adjusted LinkedIn and Google spend
with seasonality features. Key findings from ML.GLOBAL_EXPLAIN:

| Rank | Feature               | Attribution Score |
|------|-----------------------|-------------------|
| 1    | month_of_year         | 208.8             |
| 2    | quarter               | 206.7             |
| 3    | spend_events          | 124.5             |
| 4    | adstock_spend_google  | 90.6              |
| 5    | adstock_spend_linkedin| 84.8              |
| 6    | day_of_week           | 19.5              |
| 7    | spend_email           | 0.0               |

**Finding:** Seasonality explains more CAC variance than channel spend choices —
suggesting timing optimisation is undervalued relative to channel mix decisions
in B2B marketing. Current R²=0.27 reflects day-level noise; a CRM-enhanced
version incorporating deal size and ICP score is planned (target R² > 0.60).

### 4. Cohort LTV Matrix
**File:** `models/marts/fct_cohort_ltv_matrix.sql`  
Calculates cumulative per-user LTV and retention rate by acquisition cohort
and channel. Tracks both broad activity-based LTV and closed-won-only LTV
separately — a critical B2B distinction as most cohort activity is pre-revenue
(MQL, Demo, Trial) and conflating the two overstates true revenue LTV.

### 5. Budget Pacing
**File:** `models/marts/fct_marketing_budget_pacing.sql`  
B2B-aware daily budget pacing with tiered variance thresholds:
- Paid channels (LinkedIn, Google): ±15% variance band
- Bursty channels (Events): ±40% variance band
- Zero-cost channels (Organic, Email): N/A — no pacing logic applied

### 6. Core Marketing Performance
**File:** `models/marts/fct_marketing_performance.sql`  
Central B2B fact table joining spend and engagement to full funnel conversion
stages (MQL, Demo Request, Trial Sign-up, Closed Won). Computes CAC, ROAS,
cost_per_mql, cost_per_demo, and 7-day rolling spend at campaign/channel/day
granularity.

---

## B2B Synthetic Data Design

**Folder:** `/data_generation`

All source data is synthetic, designed to mirror real B2B SaaS data quality
including intentional imperfections:

| Field       | Null Logic                          | Reason                         |
|-------------|-------------------------------------|--------------------------------|
| spend       | NULL for Organic Search + Email     | Zero-cost channels by nature   |
| impressions | NULL for Organic Search             | Not tracked at keyword level   |
| clicks      | ~3% random NULL rate                | Ad platform reporting gaps     |
| sessions    | ~2% random NULL rate                | GA4 session drop-off           |

**B2B channel set:** LinkedIn Ads · Google Ads · Organic Search · Email · Events  
**B2B conversion funnel:** MQL (35%) · Demo Request (30%) · Trial Sign-up (25%) · Closed Won (10%)  
**Revenue range:** £500–£25,500 ACV (Closed Won events only)

---

## What I'd Add With More Time

### Multi-Touch Attribution (In Progress — ETA 2 weeks)
Last-touch attribution understates the contribution of awareness channels
(LinkedIn, Organic) in long B2B sales cycles where deals have 6–15 touchpoints
over 3–12 months. Building:
- `gen_event_touchpoints_raw.sql` — user journey touchpoint generator
- `fct_attribution_linear.sql` — equal credit across all touchpoints
- `fct_attribution_position.sql` — 40/20/40 U-shaped model
- `fct_attribution_comparison.sql` — last-touch vs linear vs position side by side

### CRM-Enhanced CAC Model (Month 2)
The current cac_spend_predictor achieves R²=0.27 using spend inputs alone.
The remaining 73% of CAC variance is driven by deal size, ICP fit, and
pipeline velocity — factors not yet in the model. Planning to build:
- `gen_crm_opportunities_raw.sql` — opportunity pipeline with deal size tiers and ICP scores
- `fct_crm_opportunity_pipeline.sql` — pipeline velocity and win rate by channel
- `cac_spend_predictor_v2.sql` — CRM-enhanced model targeting R² > 0.60

### Production Enhancements
- **dbt:** Migrate stored procedures to dbt models with schema tests,
  documentation, and scheduled runs replacing manual execution
- **Python:** Hill saturation curves for MMM diminishing returns modelling
  (beyond adstock decay)
- **Account-based attribution:** Group touchpoints by company domain rather
  than individual user_id — more accurate for B2B buying committees
- **Scheduled queries:** Replace manual stored procedure execution with
  daily scheduled refreshes
