CREATE OR REPLACE MODEL `growth-dashboard-portfolio.marketing_data.revenue_prediction_model`
OPTIONS(
  model_type='linear_reg',
  input_label_cols=['total_revenue'],
  data_split_method='seq',
  data_split_eval_fraction=0.2
) AS
SELECT
  date,
  adstock_spend_google_ads,
  adstock_spend_meta_ads,
  spend_organic_search,
  spend_email,
  impressions_google_ads,
  impressions_meta_ads,
  EXTRACT(DAYOFWEEK FROM date) AS day_of_week,
  EXTRACT(MONTH FROM date) AS month,
  total_revenue
FROM
  `growth-dashboard-portfolio.marketing_data.fct_marketing_mmm_features`
WHERE
  total_revenue IS NOT NULL;
