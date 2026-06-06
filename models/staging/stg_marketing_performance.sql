-- stg_marketing_performance.sql
-- Source: marketing_data.marketing_perf_raw
-- Cleans and types raw B2B marketing performance data.
-- Handles intentional nulls from zero-cost channels.
--
-- Channel null reference:
--   LinkedIn Ads    spend populated, impressions populated
--   Google Ads      spend populated, impressions populated
--   Organic Search  spend NULL (zero-cost), impressions NULL (not tracked)
--   Email           spend NULL (zero-cost), impressions NULL (send volume tracked separately)
--   Events          spend populated (bursty — many days = 0.0), impressions NULL

SELECT
  date,
  campaign_id,
  channel,
  source_medium,
  -- Impressions: NULL for organic/email/events by design — COALESCE to 0 for aggregation
  COALESCE(CAST(impressions AS INT64),   0)       AS impressions,
  COALESCE(CAST(clicks AS INT64),        0)       AS clicks,
  -- Spend: NULL for zero-cost channels — COALESCE to 0.0 for aggregation
  COALESCE(CAST(spend AS FLOAT64),       0.0)     AS spend,
  COALESCE(CAST(sessions AS INT64),      0)       AS sessions,
  -- Derived: TRUE for channels with trackable media cost
  CASE
    WHEN channel IN ('Organic Search', 'Email') THEN FALSE
    ELSE TRUE
  END                                             AS is_paid_channel

FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
WHERE date IS NOT NULL;
