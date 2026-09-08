class PpRecord < ApplicationRecord
  # Governed content types. Delegation of Authority comes in two tiers, and both
  # are governed documents rather than a separate register: an executive matrix
  # assigns authority to org units (positions), and an operational matrix does
  # the same inside one procedure, for the job titles that execute it. SLAs and
  # the glossary are governed the same way, so they live here too.
  TYPES = %w[
    policy procedure work_instruction form service guideline charter
    executive_doa operational_doa sla glossary
  ].freeze

  # The two authority matrices. The operational one must conform to the
  # executive one, which is why they are named together.
  DOA_TYPES = %w[executive_doa operational_doa].freeze

  # Types that document how work is carried out must hang off a process; the
  # enterprise-wide types may stand alone.
  # Types that document how work is carried out and so cannot stand alone.
  PROCESS_REQUIRED_TYPES = %w[procedure work_instruction form operational_doa].freeze

  # Of those, the ones actually validated. The rule was declared when the module
  # was built but never enforced, so live records of the older three may already
  # have no process; validating them now would make those records uneditable.
  # An operational matrix is new, so it can be held to the rule from the start.
  # Backfilling the rest needs a data check first — see the audit note.
  PROCESS_ENFORCED_TYPES = %w[operational_doa].freeze

  # Stages that count as "done" for package progress. The Documenter (Phase 3)
  # owns the full sequence; these are the terminal ones.
  COMPLETED_STAGES = %w[s5_published s5_closed].freeze

  # Raised when a record already sits in another package and the caller has not
  # explicitly asked to move it.
  class PackageConflict < StandardError
    attr_reader :record, :current_package

    def initialize(record, current_package)
      @record = record
      @current_package = current_package
      super("Record is already in package #{current_package&.name}")
    end
  end

  belongs_to :company
  belongs_to :package, class_name: "PpPackage", optional: true
  belongs_to :owner_user, class_name: "User", optional: true
  belongs_to :owner_org_unit, class_name: "OrgUnit", optional: true
  belongs_to :pp_process, class_name: "PpProcess", optional: true

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  has_many :record_terms, -> { ordered }, class_name: "PpRecordTerm", foreign_key: "pp_record_id", dependent: :destroy
  has_many :glossary_terms, through: :record_terms
  has_many :references, -> { ordered }, class_name: "PpRecordReference", foreign_key: "pp_record_id", dependent: :destroy

  has_many :stage_transitions, class_name: "PpStageTransition", dependent: :destroy
  has_many :stage_approvals, class_name: "PpStageApproval", dependent: :destroy
  has_many :stage_assignees, class_name: "PpStageAssignee", dependent: :destroy
  has_many :diagrams, -> { order(created_at: :desc) }, as: :owner, class_name: "PpDiagram", dependent: :destroy
  belongs_to :previous_version, class_name: "PpRecord", optional: true
  has_one :next_version, class_name: "PpRecord", foreign_key: "previous_version_id", dependent: :nullify

  validates :record_type, presence: true, inclusion: { in: TYPES }
  validates :classification, inclusion: { in: DocumentClassification::KEYS }
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :code, uniqueness: { scope: :company_id }, allow_blank: true
  validates :title_en, length: { maximum: 300 }
  validates :title_ar, length: { maximum: 300 }
  validates :version_label, length: { maximum: 50 }, allow_blank: true
  validate :must_have_a_title
  validate :package_must_be_same_company
  validate :process_must_be_same_company
  validate :review_after_effective
  validate :process_required_for_type

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:record_type, :code, :created_at) }
  scope :of_type, ->(type) { where(record_type: type) }
  scope :unpackaged, -> { where(package_id: nil) }
  scope :in_package, ->(package) { where(package_id: package.id) }
  scope :due_for_review, ->(on = Date.current) { where(review_date: ..on) }

  def classification_label(locale = I18n.locale)
    DocumentClassification.label(classification, locale)
  end

  # Only a record classified public may be shown outside the company.
  def externally_publishable?
    DocumentClassification.publishable?(classification)
  end

  def doa?
    DOA_TYPES.include?(record_type)
  end

  def display_title(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ title_ar, title_en ] : [ title_en, title_ar ]
    primary.presence || fallback.presence || code.presence || ""
  end

  def type_label(locale = I18n.locale)
    I18n.t("pp_records.types.#{record_type}", locale: locale, default: record_type.to_s.humanize)
  end

  def completed?
    COMPLETED_STAGES.include?(current_stage.to_s)
  end

  def packaged?
    package_id.present?
  end

  # Days until the review date; negative once overdue. nil when not scheduled.
  def days_until_review(from = Date.current)
    return nil if review_date.blank?

    (review_date - from).to_i
  end

  def review_overdue?(from = Date.current)
    review_date.present? && review_date < from
  end

  def review_due_soon?(lead_days = 30, from = Date.current)
    days = days_until_review(from)
    days.present? && days >= 0 && days <= lead_days
  end

  # Composition happens from the package side only. Assigning a record that is
  # already committed to a DIFFERENT package raises PackageConflict unless the
  # caller explicitly re-assigns, so a package can never silently steal another
  # package's record.
  def assign_to_package!(new_package, reassign: false)
    return true if package_id == new_package&.id

    if package_id.present? && new_package.present? && !reassign
      raise PackageConflict.new(self, package)
    end

    update!(package: new_package)
  end

  def remove_from_package!
    update!(package: nil)
  end

  # ---- Lifecycle (Documenter) -------------------------------------------

  def stage_key
    current_stage.presence || PpStage::FIRST_KEY
  end

  def stage_label(locale = I18n.locale)
    PpStage.label(stage_key, locale)
  end

  def stage_phase
    PpStage.phase_of(stage_key)
  end

  def terminal_stage?
    PpStage.terminal?(stage_key)
  end

  # The one legal forward destination for THIS record, computed from its type
  # and its intersections answer. nil at the end of the route.
  def next_stage_key
    PpStage.next_key(stage_key, record_type: record_type, has_intersections: has_intersections?)
  end

  def route
    PpStage.route_for(record_type: record_type, has_intersections: has_intersections?)
  end

  # How far along the route the record is, 0..1 — used by the funnel.
  def route_position
    route.index(stage_key)
  end

  # Working days sitting in the current stage, from the system timestamp of the
  # transition that put it here.
  def working_days_in_stage(now = Time.current)
    WorkingDaysService.between(company, stage_entered_at || created_at, now)
  end

  def stage_target_days
    PpStageTarget.days_for(company, stage_key)
  end

  # Late = sitting longer than this stage's target. Approval stages are judged
  # on the chain (the slowest outstanding unit), never on a typed date.
  def stage_late?(now = Time.current)
    return false if terminal_stage?

    target = stage_target_days
    return false if target <= 0

    working_days_in_stage(now) > target
  end

  def approvals_for_current_stage
    stage_approvals.for_stage(stage_key)
  end

  def approvals_complete?(key = stage_key)
    scope = stage_approvals.for_stage(key)
    scope.any? && scope.pending.none?
  end

  private

  def must_have_a_title
    return if title_en.to_s.strip.present? || title_ar.to_s.strip.present?

    errors.add(:base, I18n.t("pp_records.errors.title_required"))
  end

  def package_must_be_same_company
    return if package.nil? || package.company_id == company_id

    errors.add(:package_id, I18n.t("pp_records.errors.package_other_company"))
  end

  def process_must_be_same_company
    return if pp_process.nil? || pp_process.company_id == company_id

    errors.add(:pp_process_id, I18n.t("pp_records.errors.process_other_company"))
  end

  def review_after_effective
    return if effective_date.blank? || review_date.blank? || review_date >= effective_date

    errors.add(:review_date, I18n.t("pp_records.errors.review_before_effective"))
  end

  def process_required_for_type
    return unless PROCESS_ENFORCED_TYPES.include?(record_type)
    return if pp_process_id.present?

    errors.add(:pp_process_id, I18n.t("pp_records.errors.process_required"))
  end
end
