class Language < ApplicationRecord
  skip_activity_trail
  # Validations
  validates :code, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :name, presence: true, length: { maximum: 100 }
  validates :direction, presence: true, inclusion: { in: %w[ltr rtl] }

  # Associations
  has_many :standard_translations, foreign_key: "language_code", primary_key: "code", dependent: :destroy
  has_many :clause_translations, foreign_key: "language_code", primary_key: "code", dependent: :destroy
  has_many :checklist_item_translations, foreign_key: "language_code", primary_key: "code", dependent: :destroy

  # Scopes
  scope :ltr, -> { where(direction: "ltr") }
  scope :rtl, -> { where(direction: "rtl") }

  # Instance methods
  def ltr?
    direction == "ltr"
  end

  def rtl?
    direction == "rtl"
  end
end
