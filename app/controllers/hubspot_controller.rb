
class HubspotController < AdminController
  def index
    @sync_statuses = HubspotSyncStatus.order(updated_at: :desc).limit(20)
    @object_types = HubspotBigquerySyncJob::HUBSPOT_OBJECTS.keys.map(&:to_s)

    # Get last sync time for each object type
    @last_syncs = {}
    @object_types.each do |object_type|
      @last_syncs[object_type] = HubspotSyncStatus.last_successful_sync(object_type)
    end

    # Show any error logs that might be related to Hubspot
    @error_logs = ErrorLog.where("title LIKE ?", "%Hubspot%").order(created_at: :desc).limit(5)
  end

  def sync
    object_type = params[:object_type]
    full_sync = params[:full_sync] == "true"

    if object_type.present?
      # Mark as in progress
      HubspotSyncStatus.create_or_update(
        object_type: object_type,
        status: "in_progress"
      )

      # Queue the sync job
      HubspotBigquerySyncJob.perform_later(object_type, full_sync: full_sync)

      flash[:notice] = "#{full_sync ? 'Full sync' : 'Incremental sync'} job for #{object_type} has been queued"
    else
      # Mark all as in progress
      HubspotBigquerySyncJob::HUBSPOT_OBJECTS.keys.each do |type|
        HubspotSyncStatus.create_or_update(
          object_type: type.to_s,
          status: "in_progress"
        )
      end

      # Queue sync job for all objects
      HubspotBigquerySyncJob.perform_later(nil, full_sync: full_sync)

      flash[:notice] = "#{full_sync ? 'Full sync' : 'Incremental sync'} job for all Hubspot objects has been queued"
    end

    redirect_to hubspot_index_path
  end

  def schema_update
    object_type = params[:object_type]

    if object_type.present?
      # Queue the schema update job
      HubspotSchemaUpdateJob.perform_later(object_type)
      flash[:notice] = "Schema update job for #{object_type} has been queued"
    else
      # Queue schema update job for all core objects
      HubspotSchemaUpdateJob.perform_later(nil)
      flash[:notice] = "Schema update job for all core Hubspot objects has been queued"
    end

    redirect_to hubspot_index_path
  end

  def run_console
    if Rails.env.development?
      object_type = params[:object_type]
      full_sync = params[:full_sync] == "true"

      begin
        result = if object_type.present?
          HubspotBigquerySyncJob.run_now(object_type, full_sync: full_sync)
        else
          HubspotBigquerySyncJob.run_now(full_sync: full_sync)
        end

        flash[:notice] = "Sync job completed successfully"
      rescue => e
        flash[:error] = "Error running sync job: #{e.message}"
        Rails.logger.error("Error running sync job from console: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      end

      redirect_to hubspot_index_path
    else
      flash[:error] = "This feature is only available in development mode"
      redirect_to hubspot_index_path
    end
  end
end
