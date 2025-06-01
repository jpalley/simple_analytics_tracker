class ErrorRequestsController < AdminController
  def index
    @error_requests = ErrorRequest.order(timestamp: :desc)

    # Apply filters if provided
    @error_requests = @error_requests.where(status_code: params[:status_code]) if params[:status_code].present?
    @error_requests = @error_requests.where(request_method: params[:method]) if params[:method].present?
    @error_requests = @error_requests.where("path LIKE ?", "%#{params[:path]}%") if params[:path].present?

    # Date range filter
    if params[:start_date].present? && params[:end_date].present?
      begin
        start_date = Date.parse(params[:start_date]).beginning_of_day
        end_date = Date.parse(params[:end_date]).end_of_day
        @error_requests = @error_requests.where(timestamp: start_date..end_date)
      rescue Date::Error
        # Ignore invalid dates and continue without date filtering
        flash.now[:warning] = "Invalid date format provided. Date filter was ignored."
      end
    end

    # Get filtered results for display (limited)
    @error_requests_limited = @error_requests.limit(100)

    # Statistics for the filtered results (before limiting)
    # Create a separate query without the ordering to avoid GROUP BY issues
    filtered_query = @error_requests.reorder("")  # Remove the ordering for statistics

    @total_errors = filtered_query.count
    @status_code_breakdown = filtered_query.group(:status_code).count
    @method_breakdown = filtered_query.group(:request_method).count
    @path_breakdown = filtered_query.group(:path).limit(10).count

    # Use the limited results for display
    @error_requests = @error_requests_limited
  end

  def show
    @error_request = ErrorRequest.find(params[:id])
  end

  def destroy_all
    ErrorRequest.destroy_all
    redirect_to error_requests_path, notice: "All error requests have been deleted."
  end
end
