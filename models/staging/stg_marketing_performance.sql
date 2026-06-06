-- stg_marketing_performance.sql
-- Reads from: marketing_data.marketing_perf_raw
-- Cleans nulls, casts types, documents intentional null logic

SELECT
  date,
  campaign_id,
  channel,
  source_medium,
  COALESCE(impressions, 0)        AS impressions,
  COALESCE(clicks, 0)             AS clicks,
  -- Spend is intentionally null for Organic and Email (zero-cost channels)
  COALESCE(spend, 0.0)            AS spend,
  COALESCE(sessions, 0)           AS sessions
FROM `growth-dashboard-portfolio.marketing_data.marketing_perf_raw`
WHERE date IS NOT NULL
