-- fct_cohort_ltv_matrix.sql
-- Cohort-based Customer Lifetime Value (LTV) analysis for B2B SaaS.
-- Tracks cumulative revenue and retention per acquisition cohort over time,
-- enabling comparison of LTV curves across channels and acquisition months.
--
-- B2B context:
--   B2B SaaS LTV analysis differs from B2C in three important ways:
--   1. REVENUE EVENTS ARE SPARSE: Only 'Closed Won' conversions generate
--      revenue (ACV £500–£25,500). Most cohort-months will show £0 period
--      revenue as the majority of conversions are MQL/Demo/Trial.
--      This is expected and reflects real B2B funnel economics.
--   2. LONGER TIME-TO-VALUE: B2B cohorts may not generate revenue until
--      2–3 months after acquisition as deals move through the sales cycle.
--      Cohort age month 0 revenue will typically be low.
--   3. ACQUISITION CHANNEL MATTERS MORE: In B2B, LinkedIn-acquired users
--      typically have higher ACV than organic or email-acquired users.
--      This model surfaces that difference via acquisition_channel grouping.
--
-- Retention definition used here:
--   A user is considered 'active' in a cohort age month if they have
--   any conversion event (MQL, Demo, Trial, or Closed Won) in that period.
--   This is a broad retention definition — in production you would use
--   product login events or CRM stage progression as the activity signal.
--
-- Known limitations (production enhancements flagged):
--   1. USER IDENTITY: user_id is randomly generated in the source, meaning
--      the same real user could appear under multiple IDs. Production would
--      use a deterministic user identity resolution layer.
--   2. CHANNEL JOIN: Currently joins to dim_campaigns for channel lookup.
--      A production model would join to a properly maintained campaign
--      dimension table with SCD (slowly changing dimension) support.
--   3. REVENUE TIMING: Revenue is attributed to the conversion_date of the
--      Closed Won event. Production would use contract start date or
--      invoice date for more accurate ARR/MRR recognition.
--   4. STORED PROCEDURE: Requires manual execution. Production equivalent
--      would be a scheduled query or dbt model running daily.
--
-- Source: marketing_data.conversion_raw
-- Dimension: marketing_data.dim_campaigns
-- Output: marketing_data.fct_cohort_ltv_matrix

CREATE OR REPLACE PROCEDURE `growth-dashboard-portfolio.marketing_data.sp_analytics_cohort_ltv`()
BEGIN

  CREATE OR REPLACE TABLE `growth-dashboard-portfolio.marketing_data.fct_cohort_ltv_matrix` AS

  -- 1. Identify the first conversion event for every user (acquisition profile)
  --    First event defines their acquisition cohort month and source campaign.
  --    ARRAY_AGG pattern captures the campaign at exact acquisition moment
  --    rather than a MAX/MIN which could return inconsistent results.
  WITH user_acquisition AS (
    SELECT
      user_id,
      MIN(conversion_date)                                              AS acquisition_date,
      DATE_TRUNC(MIN(conversion_date), MONTH)                          AS acquisition_cohort_month,
      ARRAY_AGG(campaign_id ORDER BY conversion_date ASC LIMIT 1)[OFFSET(0)] AS acquisition_campaign_id,
      -- B2B addition: capture the first conversion type to understand
      -- what top-of-funnel action initially brought the user in
      ARRAY_AGG(conversion_type ORDER BY conversion_date ASC LIMIT 1)[OFFSET(0)] AS acquisition_conversion_type
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw`
    GROUP BY user_id
  ),

  -- 2. Map every conversion event back to the user's acquisition profile
  --    Includes all conversion types — revenue-generating events are sparse
  --    in B2B but pre-revenue events (MQL, Demo, Trial) are tracked for
  --    retention calculation purposes.
  transaction_lifecycle AS (
    SELECT
      c.user_id,
      ua.acquisition_cohort_month,
      ua.acquisition_campaign_id,
      ua.acquisition_conversion_type,
      c.conversion_date,
      c.conversion_type,
      COALESCE(c.revenue, 0.0)                                          AS revenue,
      -- Months elapsed since acquisition — defines the cohort age axis
      DATE_DIFF(
        DATE_TRUNC(c.conversion_date, MONTH),
        ua.acquisition_cohort_month,
        MONTH
      )                                                                  AS cohort_age_month
    FROM `growth-dashboard-portfolio.marketing_data.conversion_raw` c
    INNER JOIN user_acquisition ua
      ON c.user_id = ua.user_id
  ),

  -- 3. Cohort baseline sizes: how many unique users acquired per cohort month
  --    Used as the denominator for LTV per user and retention rate calculations
  cohort_sizes AS (
    SELECT
      acquisition_cohort_month,
      acquisition_campaign_id,
      COUNT(DISTINCT user_id)     AS total_cohort_users
    FROM user_acquisition
    GROUP BY 1, 2
  ),

  -- 4. Aggregate revenue and active user counts by cohort month and age
  --    active_users_in_period counts any user with a conversion event that month
  --    regardless of type — broad retention proxy (see header note on limitation)
  cohort_revenue_steps AS (
    SELECT
      acquisition_cohort_month,
      acquisition_campaign_id,
      cohort_age_month,
      COUNT(DISTINCT user_id)     AS active_users_in_period,
      SUM(revenue)                AS period_revenue,
      -- B2B addition: track closed won events separately from total activity
      SUM(CASE WHEN conversion_type = 'Closed Won' THEN revenue ELSE 0.0 END) AS period_closed_won_revenue,
      COUNT(CASE WHEN conversion_type = 'Closed Won' THEN 1 END)              AS period_closed_won_count
    FROM transaction_lifecycle
    GROUP BY 1, 2, 3
  )

  -- 5. Final assembly: LTV curves, retention rates, and B2B funnel metrics
  SELECT
    r.acquisition_cohort_month,
    -- Channel lookup via dim_campaigns (one row per campaign_id)
    -- Replaces direct join to marketing_perf_raw which could fan out rows
    dc.channel                                                          AS acquisition_channel,
    r.cohort_age_month,
    s.total_cohort_users,
    r.active_users_in_period,

    -- Retention rate: % of original cohort still active in this period
    ROUND(
      SAFE_DIVIDE(r.active_users_in_period, s.total_cohort_users) * 100,
      2
    )                                                                   AS retention_rate_pct,

    ROUND(r.period_revenue, 2)                                          AS gross_period_revenue,
    ROUND(r.period_closed_won_revenue, 2)                               AS period_closed_won_revenue,
    r.period_closed_won_count,

    -- Cumulative cohort revenue: running total of all revenue for this cohort
    ROUND(
      SUM(r.period_revenue) OVER (
        PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
        ORDER BY r.cohort_age_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      2
    )                                                                   AS cumulative_cohort_revenue,

    -- Cumulative LTV per user: revenue per head since acquisition
    ROUND(
      SAFE_DIVIDE(
        SUM(r.period_revenue) OVER (
          PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
          ORDER BY r.cohort_age_month
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        s.total_cohort_users
      ),
      2
    )                                                                   AS cumulative_per_user_ltv,

    -- B2B addition: cumulative closed won LTV only (excludes pre-revenue events)
    -- Useful for comparing true revenue LTV vs broad activity-based LTV
    ROUND(
      SAFE_DIVIDE(
        SUM(r.period_closed_won_revenue) OVER (
          PARTITION BY r.acquisition_cohort_month, r.acquisition_campaign_id
          ORDER BY r.cohort_age_month
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        s.total_cohort_users
      ),
      2
    )                                                                   AS cumulative_closed_won_ltv_per_user

  FROM cohort_revenue_steps r
  LEFT JOIN cohort_sizes s
    ON  r.acquisition_cohort_month  = s.acquisition_cohort_month
    AND r.acquisition_campaign_id   = s.acquisition_campaign_id
  LEFT JOIN `growth-dashboard-portfolio.marketing_data.dim_campaigns` dc
    ON r.acquisition_campaign_id = dc.campaign_id

  ORDER BY acquisition_cohort_month ASC, cohort_age_month ASC;

END;
