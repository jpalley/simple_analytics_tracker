class AddNotificationSentToErrorLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :error_logs, :notification_sent, :boolean, default: false
  end
end
