class StandardTranslation < ApplicationRecord
  skip_activity_trail
  # Validations
  validates :standard_id, presence: true
  validates :language_code, presence: true, length: { maximum: 10 }
  validates :name, presence: true, length: { maximum: 255 }

  # Associations
  belongs_to :standard
  belongs_to :language, foreign_key: "language_code", primary_key: "code"

  # Scopes
  scope :for_language, ->(code) { where(language_code: code) }
end
