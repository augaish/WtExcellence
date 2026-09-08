# A grant of an authority from one position to another.
#
# From and to are organizational units, never users: «تفويض الصلاحيات للمنصب
# وليس للشخص… تتوقف صلاحيات الشخص بتركه المنصب». A delegation therefore survives
# a change of postholder, which is the point of it.
#
# The rules enforced here are the ones the guiding principles state in prose and
# no register can check for itself.
class AuthorityDelegation < ApplicationRecord
  belongs_to :company
  belongs_to :authority
  belongs_to :from_org_unit, class_name: "OrgUnit"
  belongs_to :to_org_unit, class_name: "OrgUnit"
  belongs_to :decision_record, class_name: "PpRecord", optional: true
  belongs_to :parent_delegation, class_name: "AuthorityDelegation", optional: true
  belongs_to :grantor_approved_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  has_many :sub_delegations, class_name: "AuthorityDelegation",
    foreign_key: "parent_delegation_id", dependent: :restrict_with_error

  KINDS = %w[permanent temporary acting].freeze
  STATUSES = %w[draft active revoked].freeze

  # How long before expiry a delegation is worth warning about, matching the
  # review-date lead used elsewhere.
  EXPIRY_LEAD_DAYS = 30

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :limit_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  validate :units_must_be_same_company
  validate :cannot_delegate_to_itself
  validate :cannot_form_a_cycle
  validate :temporary_delegation_needs_an_end_date
  validate :end_date_must_follow_start_date
  validate :cannot_exceed_the_holder_s_own_limit
  validate :sub_delegation_needs_the_original_grantor_s_approval
  validate :sub_delegation_may_not_be_re_delegated
  validates :revocation_reason, presence: true, if: :revoked?

  before_save :stamp_revocation

  scope :active_status, -> { where(status: "active") }
  scope :ordered, -> { order(:valid_to, :created_at) }
  scope :expiring_before, ->(date) { active_status.where(valid_to: ..date).where.not(valid_to: nil) }

  def revoked?
    status == "revoked"
  end

  # In force right now: active, started, and not yet lapsed. A temporary
  # delegation stops conferring authority the moment it expires — nobody has to
  # remember to switch it off.
  def in_force?(on = Date.current)
    return false unless status == "active"
    return false if valid_from.present? && on < valid_from
    return false if valid_to.present? && on > valid_to

    true
  end

  def expired?(on = Date.current)
    status == "active" && valid_to.present? && on > valid_to
  end

  def expiring_soon?(on = Date.current, lead = EXPIRY_LEAD_DAYS)
    return false unless status == "active" && valid_to.present?

    (on..on + lead).cover?(valid_to)
  end

  # What the delegate may actually decide: their own cap where one is set,
  # otherwise the holder's.
  def effective_limit
    limit_amount || holder_limit
  end

  def kind_label(locale = I18n.locale)
    I18n.t("doa.delegation.kinds.#{kind}", locale: locale)
  end

  # Even when a delegation is exercised, «تبقى المساءلة على عاتق صاحب الصلاحية
  # الأصلي» — the original holder remains accountable, whatever the chain length.
  def accountable_unit
    root = self
    root = root.parent_delegation while root.parent_delegation
    root.from_org_unit
  end

  private

  # The largest amount the delegating position may itself decide, taken from the
  # bands the executive matrix assigns to it.
  def holder_limit
    return nil if authority.nil? || from_org_unit.nil?

    bands = authority.bands.select do |band|
      band.assignments.any? { |assignment| assignment.org_unit_id == from_org_unit_id }
    end
    return nil if bands.empty?
    # An unbounded band means no cap at all.
    return nil if bands.any? { |band| band.max_amount.blank? }

    bands.filter_map(&:max_amount).max
  end

  def units_must_be_same_company
    [ [ :from_org_unit, from_org_unit ], [ :to_org_unit, to_org_unit ] ].each do |field, unit|
      next if unit.nil? || unit.company_id == company_id

      errors.add(field, I18n.t("doa.errors.other_company"))
    end
  end

  def cannot_delegate_to_itself
    return if from_org_unit_id.blank? || from_org_unit_id != to_org_unit_id

    errors.add(:to_org_unit, I18n.t("doa.delegation.errors.self_delegation"))
  end

  # A delegates to B and B back to A for the same authority leaves nobody able
  # to say where the authority rests.
  def cannot_form_a_cycle
    return if from_org_unit_id.blank? || to_org_unit_id.blank? || authority_id.blank?

    reverse = AuthorityDelegation.where(authority_id: authority_id, status: "active",
      from_org_unit_id: to_org_unit_id, to_org_unit_id: from_org_unit_id)
    reverse = reverse.where.not(id: id) if persisted?
    return unless reverse.exists?

    errors.add(:base, I18n.t("doa.delegation.errors.circular"))
  end

  def temporary_delegation_needs_an_end_date
    return unless kind == "temporary" && valid_to.blank?

    errors.add(:valid_to, I18n.t("doa.delegation.errors.temporary_needs_end"))
  end

  def end_date_must_follow_start_date
    return if valid_from.blank? || valid_to.blank? || valid_to >= valid_from

    errors.add(:valid_to, I18n.t("doa.delegation.errors.end_before_start"))
  end

  # «يجب أن تتناسب الصلاحيات المفوضة مع المستوى الوظيفي» — and above all, nobody
  # may hand on more than they hold. This is the rule auditors actually test.
  def cannot_exceed_the_holder_s_own_limit
    cap = holder_limit
    return if cap.blank? || limit_amount.blank? || limit_amount <= cap

    errors.add(:limit_amount, I18n.t("doa.delegation.errors.exceeds_holder", limit: cap.to_i))
  end

  def sub_delegation_needs_the_original_grantor_s_approval
    return if parent_delegation.nil? || grantor_approved_by_id.present? || status != "active"

    errors.add(:base, I18n.t("doa.delegation.errors.needs_grantor_approval"))
  end

  # One documented hop. Unbounded re-delegation is how authority leaves the org
  # chart without anyone deciding that it should.
  def sub_delegation_may_not_be_re_delegated
    return if parent_delegation.nil? || parent_delegation.parent_delegation_id.blank?

    errors.add(:base, I18n.t("doa.delegation.errors.second_hop"))
  end

  def stamp_revocation
    return unless status_changed?

    if revoked?
      self.revoked_at = Time.current
      self.revoked_by ||= Thread.current[:current_user]
    else
      self.revoked_at = nil
      self.revoked_by = nil
      self.revocation_reason = nil
    end
  end
end
