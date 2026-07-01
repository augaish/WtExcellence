class RiskWorkspace < ApplicationRecord
  belongs_to :company
  has_many :risks, dependent: :nullify

  validates :name, presence: true, length: { maximum: 200 }

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end
end
