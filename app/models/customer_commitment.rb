class CustomerCommitment < ApplicationRecord
  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, {
    open: "open",
    in_progress: "in_progress",
    fulfilled: "fulfilled",
    overdue: "overdue"
  }, default: "open"

  validates :title, presence: true
  validates :customer_name, presence: true

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :due_soon, -> { active.where(due_date: Date.current..30.days.from_now).where.not(status: "fulfilled") }
  scope :past_due, -> { active.where("due_date < ?", Date.current).where.not(status: "fulfilled") }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def past_due?
    due_date.present? && due_date < Date.current && !fulfilled?
  end
end
