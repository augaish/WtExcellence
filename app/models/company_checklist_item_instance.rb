class CompanyChecklistItemInstance < ApplicationRecord
  # Validations
  validates :company_clause_instance_id, presence: true
  validates :checklist_item_id, presence: true
  validates :status, presence: true, inclusion: {
    in: %w[not_started in_progress compliant partially_compliant not_compliant not_applicable]
  }
  validates :company_clause_instance_id, uniqueness: { scope: :checklist_item_id }

  # Associations
  belongs_to :company_clause_instance
  belongs_to :checklist_item
  belongs_to :assigned_user, class_name: "User", foreign_key: "assigned_to", optional: true
  belongs_to :last_updated_by_user, class_name: "User", foreign_key: "last_updated_by", optional: true

  # Note: These associations will be added when those models are created
  # has_many :company_checklist_item_notes, dependent: :destroy
  # has_many :company_checklist_item_evidence, dependent: :destroy

  # Scopes
  scope :not_started, -> { where(status: "not_started") }
  scope :in_progress, -> { where(status: "in_progress") }
  scope :compliant, -> { where(status: "compliant") }
  scope :partially_compliant, -> { where(status: "partially_compliant") }
  scope :not_compliant, -> { where(status: "not_compliant") }
  scope :not_applicable, -> { where(status: "not_applicable") }
  scope :assigned_to, ->(user_id) { where(assigned_to: user_id) }
  scope :due, -> { where("due_date < ?", Date.current) }
  scope :overdue, -> { where("due_date < ?", Date.current).where.not(status: [ "compliant", "not_applicable" ]) }

  # Instance methods
  def not_started?
    status == "not_started"
  end

  def in_progress?
    status == "in_progress"
  end

  def compliant?
    status == "compliant"
  end

  def partially_compliant?
    status == "partially_compliant"
  end

  def not_compliant?
    status == "not_compliant"
  end

  def not_applicable?
    status == "not_applicable"
  end

  def overdue?
    due_date.present? && due_date < Date.current && !%w[compliant not_applicable].include?(status)
  end

  def due_soon?
    due_date.present? && due_date.between?(Date.current, Date.current + 7.days) && !%w[compliant not_applicable].include?(status)
  end

  # Update status and track who updated it
  def update_status(new_status, updated_by_user_id)
    update!(
      status: new_status,
      last_updated_by: updated_by_user_id,
      last_updated_at: Time.current
    )
  end
end
