-- dim_campaigns.sql
-- Campaign dimension table providing a single row per campaign_id
-- with channel and source_medium attributes.
--
-- Purpose:
--   Acts as the authoritative lookup for campaign metadata across all
--   mart models. Replaces direct joins to marketing_perf_raw in downstream
--   models (particularly fct_cohort_ltv_matrix) which could fan out rows
--   if a campaign appears on multiple dates with different attributes.
--
-- Design note:
--   MAX() aggregation on channel and source_medium handles the unlikely
--   case of inconsistent channel labelling across dates in the raw data.
--   In production this would be replaced by a managed dimension table
--   with explicit inserts and SCD (slowly changing dimension) support.
--
-- Source: marketing_data.marketing_perf_raw
-- Output: marketing_data.dim_campaigns

CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.dim_campaigns` AS

SELECT
  campaign_id,
  MAX(channel)        AS channel,
  MAX(source_medium)  AS source_medium,
  -- Derived: channel spend classification for downstream filtering
  MAX(CASE
    WHEN channel IN ('Organic Search', 'Email') THEN 'Zero-Cost'
    WHEN channel = 'Events'                     THEN 'Bursty'
    ELSE                                             'Paid'
  END)                AS channel_spend_type
FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
GROUP BY campaign_id
ORDER BY campaign_id;
