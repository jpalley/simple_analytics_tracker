class ErrorLogMailer < ApplicationMailer
  def error_notification(error_log)
    @error_log = error_log
    mail(
      to: ENV["ERROR_NOTIFICATION_EMAIL"],
      subject: "ERROR!! New Error Log Created",
      from: ENV["SENDGRID_FROM_EMAIL"]
    )
  end
end
