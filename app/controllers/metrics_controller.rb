class MetricsController < ApplicationController
  http_basic_authenticate_with name: "admin", password: "password!1"

  def index
    @hourly_stats = HourlyStat.ordered.last(24 * 30) # Show last 24 hours of stats
  end
end
