class ErrorLog < ApplicationRecord
  after_create :send_error_notification

  private

  def send_error_notification
    return if recently_notified?

    ErrorLogMailer.error_notification(self).deliver_later
    update(notification_sent: true)
  end

  def recently_notified?
    self.class.where(notification_sent: true)
        .where('created_at > ?', 5.minutes.ago)
        .exists?
  end


end
