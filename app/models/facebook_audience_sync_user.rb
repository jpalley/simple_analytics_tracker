class FacebookAudienceSyncUser < ApplicationRecord
  belongs_to :facebook_audience_sync

  validates :hubspot_contact_id, presence: true,
            uniqueness: { scope: :facebook_audience_sync_id }

  # At least one of email_hash or phone_hash must be present
  validate :must_have_email_or_phone

  # Create a user tracking record using HubSpot contact ID
  def self.track_user(sync, hubspot_contact_id, email, phone)
    find_or_create_by(
      facebook_audience_sync: sync,
      hubspot_contact_id: hubspot_contact_id.to_s
    ) do |record|
      record.email_hash = email.present? ? Digest::SHA256.hexdigest(email.to_s.strip.downcase) : nil
      record.phone_hash = phone.present? ? Digest::SHA256.hexdigest(clean_phone_number(phone.to_s)) : nil
    end
  end

  def facebook_user_data
    data = {}
    data["EMAIL"] = [ email_hash ] if email_hash.present?
    data["PHONE"] = [ phone_hash ] if phone_hash.present?
    data
  end

  private

  def must_have_email_or_phone
    if email_hash.blank? && phone_hash.blank?
      errors.add(:base, "Must have either email or phone")
    end
  end

  def self.clean_phone_number(phone)
    return nil if phone.blank?
    cleaned = phone.to_s.gsub(/\D/, "")
    cleaned = "1#{cleaned}" if cleaned.length == 10
    cleaned.length >= 10 ? cleaned : nil
  end
end
