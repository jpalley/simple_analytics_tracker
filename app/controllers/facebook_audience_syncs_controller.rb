class FacebookAudienceSyncsController < ApplicationController
  before_action :set_facebook_audience_sync, only: %i[ show edit update destroy ]
  before_action :initialize_bigquery_service, only: %i[ new create edit update ]

  # GET /facebook_audience_syncs
  def index
    @facebook_audience_syncs = FacebookAudienceSync.all
  end

  # GET /facebook_audience_syncs/1
  def show
  end

  # GET /facebook_audience_syncs/new
  def new
    @facebook_audience_sync = FacebookAudienceSync.new
    @available_tables = get_available_tables
  end

  # GET /facebook_audience_syncs/1/edit
  def edit
    @available_tables = get_available_tables
  end

  # POST /facebook_audience_syncs
  def create
    @facebook_audience_sync = FacebookAudienceSync.new(facebook_audience_sync_params)

    if @facebook_audience_sync.save
      redirect_to @facebook_audience_sync, notice: "Facebook audience sync was successfully created."
    else
      @available_tables = get_available_tables
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /facebook_audience_syncs/1
  def update
    if @facebook_audience_sync.update(facebook_audience_sync_params)
      redirect_to @facebook_audience_sync, notice: "Facebook audience sync was successfully updated."
    else
      @available_tables = get_available_tables
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /facebook_audience_syncs/1
  def destroy
    @facebook_audience_sync.destroy!
    redirect_to facebook_audience_syncs_path, status: :see_other, notice: "Facebook audience sync was successfully destroyed."
  end

  private

  def set_facebook_audience_sync
    @facebook_audience_sync = FacebookAudienceSync.find(params.expect(:id))
  end

  def facebook_audience_sync_params
    params.require(:facebook_audience_sync).permit(:table_name, :audience_name, :description, :enabled, :test_mode)
  end

  def initialize_bigquery_service
    @bigquery_service = BigqueryService.new
  rescue => e
    flash.now[:alert] = "Failed to initialize BigQuery service: #{e.message}"
  end

  def get_available_tables
    return [] unless @bigquery_service

    @bigquery_service.tables.map do |table|
      {
        id: "#{ENV['BIGQUERY_DATASET']}.#{table.table_id}",
        name: table.table_id,
        description: table.description
      }
    end
  rescue => e
    flash.now[:alert] = "Error fetching available tables: #{e.message}"
    []
  end
end
