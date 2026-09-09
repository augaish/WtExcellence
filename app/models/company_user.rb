class CompanyUser < ApplicationRecord
  belongs_to :company
  belongs_to :user

  has_many :capa_assignments, dependent: :destroy
  has_many :capas, through: :capa_assignments
  has_many :capa_action_assignments, dependent: :destroy
  has_many :capa_actions, through: :capa_action_assignments

  validates :role, presence: true
  validates :user_id, uniqueness: true # A user can only belong to one company
  validates :user_id, uniqueness: { scope: :company_id } # Ensure no duplicate entries for same user+company
  validates :assigned_credits, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # Company-specific roles (scoped to a company)
  # These roles apply within the context of a specific company
  ROLES = {
    company_admin: "company_admin",
    company_quality_manager: "company_quality_manager",
    company_risk_manager: "company_risk_manager",
    company_auditor: "company_auditor",
    company_contributor: "company_contributor",
    company_viewer: "company_viewer"
  }.freeze

  # Check if user has company admin role
  def company_admin?
    role == ROLES[:company_admin]
  end

  # A quality manager the company admin has named as P&P Manager: the person
  # who runs the Documenter flows.
  def pp_manager?
    pp_manager && company_quality_manager?
  end

  def company_quality_manager?
    role == ROLES[:company_quality_manager]
  end

  def company_risk_manager?
    role == ROLES[:company_risk_manager]
  end

  def company_auditor?
    role == ROLES[:company_auditor]
  end

  def company_contributor?
    role == ROLES[:company_contributor]
  end

  def company_viewer?
    role == ROLES[:company_viewer]
  end

  # Check if user has admin privileges within this company
  # Quality managers have full admin privileges to see all clauses and evaluate all assignments
  # (either through company admin, quality manager role, or platform-wide admin role)
  def has_admin_privileges?
    company_admin? || company_quality_manager? || user&.platform_admin?
  end

  # Risk management: company admins have full access; risk managers are
  # scoped to the risk register (mirrors how quality managers are scoped to assessments)
  def can_manage_risks?
    company_admin? || company_risk_manager? || user&.platform_admin?
  end

  def credit_balance
    assigned_credits || 0
  end
end
