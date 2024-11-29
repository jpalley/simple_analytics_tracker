class ErrorLogsController < AdminController
  before_action :set_error_log, only: %i[ show edit update destroy ]

  # GET /error_logs or /error_logs.json
  def index
    @error_logs = ErrorLog.all.order(created_at: :desc).limit(50)
  end

  # GET /error_logs/1 or /error_logs/1.json
  def show
  end

  # GET /error_logs/new
  def new
    @error_log = ErrorLog.new
  end

  # GET /error_logs/1/edit
  def edit
  end

  # POST /error_logs or /error_logs.json
  def create
    @error_log = ErrorLog.new(error_log_params)

    respond_to do |format|
      if @error_log.save
        format.html { redirect_to @error_log, notice: "Error log was successfully created." }
        format.json { render :show, status: :created, location: @error_log }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @error_log.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /error_logs/1 or /error_logs/1.json
  def update
    respond_to do |format|
      if @error_log.update(error_log_params)
        format.html { redirect_to @error_log, notice: "Error log was successfully updated." }
        format.json { render :show, status: :ok, location: @error_log }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @error_log.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /error_logs/1 or /error_logs/1.json
  def destroy
    @error_log.destroy!

    respond_to do |format|
      format.html { redirect_to error_logs_path, status: :see_other, notice: "Error log was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_error_log
      @error_log = ErrorLog.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def error_log_params
      params.expect(error_log: [ :title, :body ])
    end
end
