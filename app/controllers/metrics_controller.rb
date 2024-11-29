class MetricsController < AdminController
  def index
    @hourly_stats = HourlyStat.ordered.last(24 * 30) # Show last 24 hours of stats
  end
end
