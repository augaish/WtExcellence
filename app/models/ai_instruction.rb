class AiInstruction < ApplicationRecord
  belongs_to :company
  belongs_to :created_by, class_name: "User", optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validate :at_least_one_language_present

  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Content for a locale, falling back to the other language so a single-language
  # instruction still contributes to prompts in either UI locale.
  def content_for(locale)
    primary = locale.to_s == "ar" ? content_ar : content_en
    fallback = locale.to_s == "ar" ? content_en : content_ar
    primary.presence || fallback.presence
  end

  private

  def at_least_one_language_present
    return if content_en.present? || content_ar.present?

    errors.add(:base, :content_required)
  end
end
