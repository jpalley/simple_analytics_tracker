class AddErrorTrackingToHourlyStats < ActiveRecord::Migration[8.0]
  def change
    add_column :hourly_stats, :error_4xx_count, :integer, default: 0
    add_column :hourly_stats, :error_5xx_count, :integer, default: 0
    add_column :hourly_stats, :error_400_count, :integer, default: 0
    add_column :hourly_stats, :error_401_count, :integer, default: 0
    add_column :hourly_stats, :error_403_count, :integer, default: 0
    add_column :hourly_stats, :error_404_count, :integer, default: 0
    add_column :hourly_stats, :error_422_count, :integer, default: 0
    add_column :hourly_stats, :error_500_count, :integer, default: 0
    add_column :hourly_stats, :error_502_count, :integer, default: 0
    add_column :hourly_stats, :error_503_count, :integer, default: 0
    add_column :hourly_stats, :total_requests_count, :integer, default: 0
  end
end
