# README

# Setup
- Create service account in GCP.
- Set service account roles to BigQuery Data Owner
- Create JSON key


# Environment Variables
- GOOGLE_CLOUD_PROJECT: This is the GCP project ID
- GOOGLE_CLOUD_CREDENTIALS: This is the JSON key you downloaded from GCP
- BIGQUERY_DATASET: This is the BigQuery dataset you want to sync to
- HUBSPOT_ACCESS_TOKEN: Private app access token for the Hubspot API


# What it does
- This will create two tables in bigquery: `web_persons` and `web_events`
- It will insert all records into the events table and upsert into the persons table
- It will set the `synced` flag to `true` for all records that were written to BigQuery

# Hubspot Integration

## Overview
This application includes functionality to sync data from Hubspot to BigQuery. It supports syncing the following Hubspot objects:
- Contacts
- Companies
- Deals
- Tickets
- Owners
- Engagements
- Deal Pipelines
- Deal Stages
- Workflows
- Properties
- Lists
- Call Records
- Meetings

## Setup
1. Create a private app in Hubspot with the necessary scopes for reading the objects you want to sync
   - Required scopes:
     - `crm.objects.contacts.read`
     - `crm.objects.companies.read`
     - `crm.objects.deals.read`
     - `crm.objects.tickets.read`
     - `crm.objects.owners.read`
     - `crm.pipelines.read`
     - `automation.read`
     - `forms-uploaded-files.read`
     - `crm.lists.read`
     - `crm.objects.custom.read`
     - `sales-email-read`
     - `e-commerce`
     - `timeline`
     - `integration-sync`
     - `forms`
     - `files`
     - `files.ui_hidden.read`
2. Generate an access token and set it as the HUBSPOT_ACCESS_TOKEN environment variable
3. Ensure your GCP service account has BigQuery Data Owner permissions

## Configuration
The sync job is configured to run every 4 hours by default. You can adjust this in the `config/recurring.yml` file.

## Tables
All Hubspot data is stored in BigQuery tables prefixed with `hubspot_`. For example:
- `hubspot_contacts`
- `hubspot_companies`
- `hubspot_deals`
- `hubspot_workflows`
- `hubspot_properties`
- etc.

## Incremental Sync
The application implements incremental sync to efficiently update BigQuery data:

- **For Core CRM Objects** (Contacts, Companies, Deals, Tickets):
  - Uses the Hubspot Search API with a `lastmodifieddate` filter to fetch only records updated since the last sync
  - Significantly reduces API usage and sync time

- **For Legacy Endpoints** (Engagements, Call Records):
  - Fetches all records but filters client-side based on timestamp
  
- **For Configuration Objects** (Pipelines, Properties, Workflows):
  - Always performs a full sync as these objects are typically small and don't change often

The controller provides options for both incremental and full sync operations through the UI.

## Property Handling
The application properly extracts and formats all Hubspot properties:

- All standard and custom properties are now included in the sync
- Property field names are cleaned up (removing the "properties_" prefix)
- Array fields are properly JSON formatted to avoid BigQuery errors
- Complex nested objects are properly flattened for BigQuery compatibility

## Rate Limiting
The application implements rate limiting based on Hubspot's API limits:
- Most APIs: 100 requests per 10 seconds
- Workflows API: 50 requests per 10 seconds 
- Lists API: 30 requests per 10 seconds
- Call Records API: 40 requests per 10 seconds
- Meetings API: 50 requests per 10 seconds

## UI
A web interface is provided at `/hubspot` to view sync status and trigger manual syncs. This interface is protected with the same basic authentication as the metrics dashboard.

The UI shows:
- Incremental vs. full sync options for each object
- Which objects support incremental sync
- Detailed success/failure information
- Filtering options by object category

## Error Handling
The sync process includes robust error handling:
- Rate limiting: The application respects Hubspot's API rate limits and implements automatic retries
- Logging: All sync attempts are logged in the `hubspot_sync_statuses` table
- Failures: Detailed error information is stored in the `error_logs` table
- Continuation: If syncing one object type fails, the job will continue with the next object type
- Development mode: Errors are logged to the console for easier debugging

## Running In Console
For debugging or manual syncing, you can run the job from the Rails console:

```ruby
# Sync a specific object type incrementally
HubspotBigquerySyncJob.run_now("contacts")

# Perform a full sync for a specific object type 
HubspotBigquerySyncJob.run_now("contacts", full_sync: true)

# Sync all objects incrementally
HubspotBigquerySyncJob.run_now

# Perform a full sync for all objects
HubspotBigquerySyncJob.run_now(full_sync: true)
```

## Implementation Details

### Hubspot Client
The `HubspotClient` service encapsulates all the API calls to Hubspot:
- Handles authentication with the Hubspot API
- Provides methods for fetching each type of object
- Normalizes responses from different API endpoints
- Implements rate limiting to avoid hitting API rate limits
- Supports both incremental and full sync options

### Sync Job
The `HubspotBigquerySyncJob` handles the sync process:
- Fetches data from Hubspot in batches
- Transforms the data into a format suitable for BigQuery
- Creates or updates BigQuery tables with appropriate schemas
- Loads the data into BigQuery
- Tracks sync status and handles errors
- Supports both incremental and full sync options

### Schema Management
The job dynamically manages BigQuery schemas:
- Automatically detects field types from the data
- Adds new columns to tables when new properties are encountered
- Handles complex nested data structures
- Properly formats array fields
- Sanitizes field names to be compatible with BigQuery
