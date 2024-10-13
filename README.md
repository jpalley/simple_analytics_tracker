# README

# Setup
- Create service account in GCP.
- Set service account roles to BigQuery Data Owner
- Create JSON key


# Environment Variables
- GOOGLE_CLOUD_PROJECT: This is the GCP project ID
- GOOGLE_CLOUD_CREDENTIALS: This is the JSON key you downloaded from GCP
- BIGQUERY_DATASET: This is the BigQuery dataset you want to sync to


# What it does
- This will create two tables in bigquery: `web_persons` and `web_events`
- It will insert all records into the events table and upsert into the persons table
- It will set the `synced` flag to `true` for all records that were written to BigQuery
