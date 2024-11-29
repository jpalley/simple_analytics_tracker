class ErrorLog < ApplicationRecord
  after_create :send_error_notification

  private

  def send_error_notification
    ErrorLogMailer.error_notification(self).deliver_later
  end
end
