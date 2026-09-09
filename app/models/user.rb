class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable

  devise :database_authenticatable, :rememberable, :validatable, :recoverable

  has_one_attached :profile_image
  has_one :company_user, dependent: :destroy
  has_one :company, through: :company_user
  belongs_to :org_unit, optional: true
  has_many :assigned_company_standards, class_name: "CompanyStandard", foreign_key: "assigned_by", dependent: :nullify
  has_many :company_standard_version_changes, class_name: "CompanyStandardVersionHistory", foreign_key: "changed_by", dependent: :nullify
  has_many :assigned_checklist_item_instances, class_name: "CompanyChecklistItemInstance", foreign_key: "assigned_to", dependent: :nullify
  has_many :updated_checklist_item_instances, class_name: "CompanyChecklistItemInstance", foreign_key: "last_updated_by", dependent: :nullify
  has_many :assessment_users, dependent: :destroy
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :invited_users, class_name: "User", foreign_key: "invited_by_id", dependent: :nullify
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  validates :email, presence: true, uniqueness: true, length: { maximum: 320 }
  validates :name, presence: true, length: { maximum: 200 }
  validates :locale_code, length: { maximum: 10 }

  # New users are inactive by default; they are activated when they accept an invitation or when an admin activates them.
  attribute :is_active, :boolean, default: false

  # Soft delete: exclude deleted users from all queries by default
  scope :deleted, -> { where.not(deleted_at: nil) }

  scope :active, -> { where(is_active: true) }
  scope :invited, -> { where.not(invitation_token: nil).where(invitation_accepted_at: nil) }
  scope :accepted_invitations, -> { where.not(invitation_accepted_at: nil) }
  scope :pending, -> { where(status: "pending") }

  def deleted?
    deleted_at.present?
  end

  # Global/system-level role (platform-wide)
  # Only super_admin applies across all companies
  # nil means regular user with no global privileges
  def super_admin?
    role == "super_admin"
  end

  # Whether the user has already dismissed the first-run user manual. Until they
  # skip/close it, the manual is shown automatically after each sign-in.
  def user_manual_seen?
    user_manual_seen_at.present?
  end

  def mark_user_manual_seen!
    update_column(:user_manual_seen_at, Time.current) unless user_manual_seen?
  end

  def company_admin?
    company_user&.company_admin?
  end


  def viewer?
    role == "viewer"
  end

  def delegated_admin?
    role == "delegated_admin"
  end

  # Platform-wide admin: not bound to a single company.
  def platform_admin?
    super_admin? || delegated_admin?
  end

  def company_quality_manager?
    company_user&.company_quality_manager?
  end

  def company_risk_manager?
    company_user&.company_risk_manager?
  end

  # Governance (risks, vendors, commitments): risk managers and admins work
  # it; quality managers read it.
  def can_manage_governance?
    company_user&.can_manage_governance? || platform_admin?
  end

  def can_view_governance?
    company_user&.can_view_governance? || platform_admin?
  end

  alias can_manage_risks? can_manage_governance?
  alias can_manage_commitments? can_manage_governance?
  alias can_manage_vendors? can_manage_governance?

  def can_manage_ai_instructions?
    platform_admin?
  end

  # A user whose company role is Risk Manager: works Governance, reads
  # Standards, P&P and the Library, and has no access to CAPA or the AI tools.
  def risk_manager_only?
    company_risk_manager? && !platform_admin?
  end

  def company_contributor?
    company_user&.company_contributor?
  end

  # Available permissions for delegated admins
  PERMISSIONS = {
    add_companies: "add_companies",
    update_company_profiles: "update_company_profiles",
    add_users: "add_users",
    increase_credit: "increase_credit",
    remove_companies: "remove_companies",
    assign_standards_to_companies: "assign_standards_to_companies",
    activate_deactivate_users: "activate_deactivate_users",
    modify_license_seats: "modify_license_seats",
    manage_tools: "manage_tools"
  }.freeze

  # Get permissions array (defaults to empty array)
  def permissions_array
    permissions.is_a?(Array) ? permissions : []
  end

  # Check if user has a specific permission
  def has_permission?(permission)
    return true if super_admin? # Super admins have all permissions
    return false unless delegated_admin?
    permissions_array.include?(permission.to_s)
  end

  # Set permissions (only for delegated admins)
  def permissions=(new_permissions)
    if delegated_admin?
      super(Array(new_permissions).map(&:to_s))
    else
      super([])
    end
  end

  # Check if user can perform admin actions (super admin or delegated admin with permissions)
  def can_manage_companies?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:add_companies]))
  end

  def can_update_company_profiles?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:update_company_profiles]))
  end

  def can_add_users?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:add_users]))
  end

  def can_increase_credit?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:increase_credit]))
  end

  def can_remove_companies?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:remove_companies]))
  end

  def can_assign_standards_to_companies?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:assign_standards_to_companies]))
  end

  def can_activate_deactivate_users?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:activate_deactivate_users]))
  end

  def can_modify_license_seats?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:modify_license_seats]))
  end

  def can_manage_tools?
    super_admin? || (delegated_admin? && has_permission?(PERMISSIONS[:manage_tools]))
  end

  # Get all terminal clauses this user has assignments for
  def assigned_terminal_clauses
    Clause.joins(tool_clause: { assessments: :assessment_users })
          .where(assessment_users: { user_id: id })
          .distinct
  end

  # Get all clauses (including parents) that this user should see
  # Returns terminal clauses they're assigned to + all parent clauses in the hierarchy
  def visible_clauses_with_hierarchy
    terminal_clauses = assigned_terminal_clauses
    visible_clause_ids = Set.new

    # For each terminal clause, add it and all its parents
    terminal_clauses.each do |clause|
      current = clause
      while current
        visible_clause_ids.add(current.id)
        current = current.parent
      end
    end

    Clause.where(id: visible_clause_ids.to_a)
  end

  # Check if user can see a specific clause
  def can_see_clause?(clause)
    return true if super_admin?
    return true if company_user&.has_admin_privileges?
    return true if company_user&.company_viewer?

    visible_clauses_with_hierarchy.exists?(id: clause.id)
  end

  # Get root clauses that this user should see
  def visible_root_clauses(standard_version)
    return standard_version.clauses.root_clauses if super_admin? || company_user&.has_admin_privileges?

    visible_clause_ids = visible_clauses_with_hierarchy.pluck(:id)
    standard_version.clauses.root_clauses.where(id: visible_clause_ids)
  end

  # Invitation methods
  def invited?
    invitation_token.present? && invitation_accepted_at.nil?
  end

  def invitation_expired?
    return false unless invitation_expires_at
    invitation_expires_at < Time.current
  end

  def invitation_valid?
    invited? && !invitation_expired?
  end

  def accept_invitation!
    update!(
      invitation_accepted_at: Time.current,
      invitation_token: nil
      # User remains inactive; an admin must activate them before they can sign in.
    )
  end

  def self.generate_invitation_token
    SecureRandom.urlsafe_base64(32)
  end

  def active_for_authentication?
    super && is_active?
  end

  def inactive_message
    is_active? ? super : :inactive
  end

  def pending?
    status == "pending"
  end

  def active_status?
    status == "active"
  end
end
