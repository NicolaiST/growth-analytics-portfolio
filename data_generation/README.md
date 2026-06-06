# Synthetic Data Generation


This folder contains the BigQuery SQL scripts used to generate
realistic synthetic data for the portfolio. All data is fictional.


## Design Decisions


The data is designed to mimic real B2B SaaS marketing data quality,
including deliberate imperfections:


| Field              | Null Logic                          | Reason                          |
|-------------------|-------------------------------------|---------------------------------|
| spend             | NULL for Organic Search + Email     | Zero-cost channels by nature    |
| impressions       | NULL for Organic Search             | Not tracked at keyword level    |
| clicks            | ~3% random NULL rate                | Ad platform reporting gaps      |
| sessions          | ~2% random NULL rate                | GA session drop-off             |


These nulls are handled downstream via COALESCE in the staging layer,
not silently ignored. This mirrors how a production pipeline would
handle source system data quality issues.


## Extending This Dataset


The generators can be modified to simulate:
- Seasonality spikes (Black Friday, January peaks)
- Campaign pauses and budget reallocation events
- Channel attribution model switching
- Multi-touch vs last-click revenue differences
