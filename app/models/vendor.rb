class Vendor < ApplicationRecord
  include GovernanceCapaLinkable

  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :risk_level, {
    unassessed: "unassessed",
    low: "low",
    medium: "medium",
    high: "high",
    critical: "critical"
  }, default: "unassessed"

  validates :name, presence: true

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end
end
