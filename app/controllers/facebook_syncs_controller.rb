class FacebookSyncsController < ApplicationController
  before_action :set_facebook_sync, only: %i[ show edit update destroy ]

  # GET /facebook_syncs or /facebook_syncs.json
  def index
    @facebook_syncs = FacebookSync.all
  end

  # GET /facebook_syncs/1 or /facebook_syncs/1.json
  def show
  end

  # GET /facebook_syncs/new
  def new
    @facebook_sync = FacebookSync.new
  end

  # GET /facebook_syncs/1/edit
  def edit
  end

  # POST /facebook_syncs or /facebook_syncs.json
  def create
    @facebook_sync = FacebookSync.new(facebook_sync_params)

    respond_to do |format|
      if @facebook_sync.save
        format.html { redirect_to @facebook_sync, notice: "Facebook sync was successfully created." }
        format.json { render :show, status: :created, location: @facebook_sync }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @facebook_sync.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /facebook_syncs/1 or /facebook_syncs/1.json
  def update
    respond_to do |format|
      if @facebook_sync.update(facebook_sync_params)
        format.html { redirect_to @facebook_sync, notice: "Facebook sync was successfully updated." }
        format.json { render :show, status: :ok, location: @facebook_sync }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @facebook_sync.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /facebook_syncs/1 or /facebook_syncs/1.json
  def destroy
    @facebook_sync.destroy!

    respond_to do |format|
      format.html { redirect_to facebook_syncs_path, status: :see_other, notice: "Facebook sync was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_facebook_sync
      @facebook_sync = FacebookSync.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def facebook_sync_params
      params.require(:facebook_sync).permit!
    end
end
