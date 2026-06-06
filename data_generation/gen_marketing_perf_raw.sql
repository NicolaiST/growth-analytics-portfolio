-- gen_marketing_perf_raw.sql
-- Generates synthetic daily B2B SaaS marketing performance data.
-- Covers Jan 2025 – May 2026 across 5 channels representing a
-- realistic B2B paid and organic media mix.
--
-- Channel design decisions:
--   LinkedIn Ads    — Primary B2B paid social channel. Higher CPM/CPC
--                     than B2C channels, lower volume but higher intent.
--   Google Ads      — Search intent capture. High CTR relative to impressions.
--   Organic Search  — Zero-cost channel. No spend, no impressions tracked
--                     at keyword level, but drives significant session volume.
--   Email           — SDR outreach + nurture sequences. No media spend.
--                     High session volume from existing contact lists.
--   Events/Webinars — Field marketing and virtual events. Bursty spend
--                     pattern (not daily), modelled as low-frequency spend.
--
-- Null design decisions:
--   spend        NULL for Organic Search and Email (zero-cost channels)
--   impressions  NULL for Organic Search (not tracked at keyword level)
--   clicks       ~3% random NULL rate (ad platform reporting gaps)
--   sessions     ~2% random NULL rate (GA4 session drop-off / sampling)

CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.marketing_perf_raw` AS

WITH date_range AS (
  SELECT date
  FROM UNNEST(
    GENERATE_DATE_ARRAY('2025-01-01', '2026-05-20', INTERVAL 1 DAY)
  ) AS date
),

channels AS (
  SELECT 'LinkedIn Ads'    AS channel, 'linkedin / cpc'       AS source_medium, 101 AS campaign_id UNION ALL
  SELECT 'Google Ads',                  'google / cpc',                           102              UNION ALL
  SELECT 'Organic Search',              'google / organic',                        103              UNION ALL
  SELECT 'Email',                       'outreach / email',                        104              UNION ALL
  SELECT 'Events',                      'events / webinar',                        105
)

SELECT
  d.date,
  c.campaign_id,
  c.channel,
  c.source_medium,

  -- Impressions
  -- LinkedIn and Google have tracked impressions; organic not tracked at keyword level;
  -- email and events use sends/registrations as proxy (modelled separately)
  CASE
    WHEN c.channel IN ('Organic Search', 'Email', 'Events') THEN NULL
    ELSE CAST(FLOOR(500 + RAND() * 30000) AS INT64)
  END AS impressions,

  -- Clicks
  -- All channels generate clicks; ~3% null rate simulates platform reporting gaps
  CASE
    WHEN RAND() < 0.03 THEN NULL
    ELSE CAST(FLOOR(10 + RAND() * 800) AS INT64)
  END AS clicks,

  -- Spend
  -- LinkedIn CPMs are significantly higher than Google for B2B audiences
  -- Organic and Email have no media cost
  -- Events spend is bursty — modelled as occasional larger spend vs daily
  CASE
    WHEN c.channel = 'Organic Search' THEN NULL
    WHEN c.channel = 'Email'          THEN NULL
    WHEN c.channel = 'LinkedIn Ads'   THEN ROUND(200  + RAND() * 2000, 2)
    WHEN c.channel = 'Google Ads'     THEN ROUND(100  + RAND() * 1500, 2)
    WHEN c.channel = 'Events'         THEN
      CASE WHEN RAND() < 0.08         -- Events spend only ~8% of days (bursty pattern)
        THEN ROUND(500 + RAND() * 5000, 2)
        ELSE 0.0
      END
  END AS spend,

  -- Sessions: ~2% null rate simulates GA4 sampling / session drop-off
  CASE
    WHEN RAND() < 0.02 THEN NULL
    ELSE CAST(FLOOR(5 + RAND() * 600) AS INT64)
  END AS sessions

FROM date_range d
CROSS JOIN channels c;
