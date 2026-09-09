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

  # The types with a tab and a journey of their own in Records. The rest stay
  # readable under "All" (the authority matrices are managed under Governance).
  TAB_TYPES = %w[policy procedure form service glossary].freeze

  # The two authority matrices. The operational one must conform to the
  # executive one, which is why they are named together.
  DOA_TYPES = %w[executive_doa operational_doa].freeze

  # Procedure card vocabularies, shared with the process card so the two read
  # the same way.
  FREQUENCIES = PpProcess::FREQUENCIES
  AUTOMATION_STATUSES = PpProcess::AUTOMATION_STATUSES
  TIME_UNITS = PpProcess::TIME_UNITS
  SERVICE_TYPES = %w[internal external].freeze

  # Types that document how work is carried out must hang off a process; the
  # enterprise-wide types may stand alone.
  # Types that document how work is carried out and so cannot stand alone.
  PROCESS_REQUIRED_TYPES = %w[procedure work_instruction form operational_doa].freeze

  # Of those, the ones actually validated. The rule was declared when the module
  # was built but never enforced, so live records of the older three may already
  # have no process; validating them now would make those records uneditable.
  # An operational matrix is new, so it can be held to the rule from the start.
  # Backfilling the rest needs a data check first — see the audit note.
  # A procedure is level 3 of the architecture, so it must hang off a level-2
  # process from the day the journeys were split by type.
  PROCESS_ENFORCED_TYPES = %w[operational_doa procedure].freeze

  # Stages that count as "done" for package progress. The Documenter (Phase 3)
  # owns the full sequence; these are the terminal ones.
  COMPLETED_STAGES = PpStage::TERMINAL_KEYS

  PUBLISH_MODES = %w[assign system].freeze

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

  # An executive matrix record governs the authorities it contains.
  has_many :authorities, -> { ordered }, foreign_key: "matrix_id", dependent: :destroy

  has_many :consultations, -> { ordered }, class_name: "AuthorityConsultation",
    foreign_key: "matrix_id", dependent: :destroy

  has_many :service_levels, -> { ordered }, class_name: "PpServiceLevel",
    foreign_key: "pp_record_id", dependent: :destroy

  has_many :record_terms, -> { ordered }, class_name: "PpRecordTerm", foreign_key: "pp_record_id", dependent: :destroy
  has_many :glossary_terms, through: :record_terms
  has_many :references, -> { ordered }, class_name: "PpRecordReference", foreign_key: "pp_record_id", dependent: :destroy

  has_many :stage_transitions, class_name: "PpStageTransition", dependent: :destroy
  has_many :stage_approvals, class_name: "PpStageApproval", dependent: :destroy
  has_many :stage_assignees, class_name: "PpStageAssignee", dependent: :destroy
  has_many :stage_tasks, class_name: "PpStageTask", dependent: :destroy
  belongs_to :verifier_user, class_name: "User", optional: true
  belongs_to :published_pdf_upload, class_name: "Upload", optional: true

  # What the document says: clauses for a policy, steps for a procedure.
  has_many :clauses, -> { ordered }, class_name: "PpRecordClause", foreign_key: "pp_record_id", dependent: :destroy
  has_many :steps, -> { ordered }, class_name: "PpProcessStep", foreign_key: "pp_record_id", dependent: :destroy
  has_many :diagrams, -> { order(created_at: :desc) }, as: :owner, class_name: "PpDiagram", dependent: :destroy
  belongs_to :previous_version, class_name: "PpRecord", optional: true
  has_one :next_version, class_name: "PpRecord", foreign_key: "previous_version_id", dependent: :nullify

  # Procedure card: what runs before and after, and what it implements or uses.
  belongs_to :predecessor_record, class_name: "PpRecord", optional: true
  belongs_to :successor_record, class_name: "PpRecord", optional: true
  has_many :links, class_name: "PpRecordLink", foreign_key: "pp_record_id", dependent: :destroy
  has_many :related_policies, -> { where(pp_record_links: { kind: "related_policy" }) },
    through: :links, source: :linked_record
  has_many :forms_used, -> { where(pp_record_links: { kind: "form_used" }) },
    through: :links, source: :linked_record

  # Service card: the units that take part besides the owning (providing) unit.
  has_many :participants, class_name: "PpRecordParticipant", foreign_key: "pp_record_id", dependent: :destroy
  has_many :participating_units, through: :participants, source: :org_unit

  validates :record_type, presence: true, inclusion: { in: TYPES }
  validates :classification, inclusion: { in: DocumentClassification::KEYS }
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :code, uniqueness: { scope: :company_id }, allow_blank: true
  validates :title_en, length: { maximum: 300 }
  validates :title_ar, length: { maximum: 300 }
  validates :counterparty, length: { maximum: 250 }
  validates :version_label, length: { maximum: 50 }, allow_blank: true
  validate :must_have_a_title
  validate :package_must_be_same_company
  validate :process_must_be_same_company
  validate :review_after_effective
  validate :process_required_for_type
  validate :procedure_process_must_be_level_two
  validate :reason_required_for_new_version
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_blank: true
  validates :automation_status, inclusion: { in: AUTOMATION_STATUSES }, allow_blank: true
  validates :total_time_unit, inclusion: { in: TIME_UNITS }, allow_blank: true
  validates :total_time_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :service_type, inclusion: { in: SERVICE_TYPES }, allow_blank: true
  validates :publish_mode, inclusion: { in: PUBLISH_MODES }, allow_blank: true
  validates :auto_approve_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :published_link, length: { maximum: 1000 }
  validates :scope, :requirements, :beneficiaries, :channels, :delivery_stages, :inputs, :outputs,
    :technical_systems, :kpis, length: { maximum: 5000 }
  validates :trigger_text, length: { maximum: 500 }
  validates :delivery_period, length: { maximum: 250 }

  before_validation :assign_code_and_sequence
  before_create :enter_first_stage

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:record_type, :code, :created_at) }
  scope :of_type, ->(type) { where(record_type: type) }
  scope :unpackaged, -> { where(package_id: nil) }
  scope :in_package, ->(package) { where(package_id: package.id) }
  scope :due_for_review, ->(on = Date.current) { where(review_date: ..on) }
  # The newest issue of each document: a record nobody has opened a next
  # version of.
  scope :latest, -> { where.not(id: PpRecord.where.not(previous_version_id: nil).select(:previous_version_id)) }

  def classification_label(locale = I18n.locale)
    DocumentClassification.label(classification, locale)
  end

  # Only a record classified public may be shown outside the company.
  def externally_publishable?
    DocumentClassification.publishable?(classification)
  end

  def sla?
    record_type == "sla"
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

  # Published means read-only: changes go through "Update existing", which
  # opens the next version.
  def editable?
    !completed? && next_version.nil?
  end

  def latest_version?
    next_version.nil?
  end

  def new_version?
    previous_version_id.present?
  end

  def procedure?
    record_type == "procedure"
  end

  def service?
    record_type == "service"
  end

  def glossary?
    record_type == "glossary"
  end

  # Level 0 . Level 1 . Level 2 . own sequence, for a procedure.
  def architecture_number
    return nil unless procedure? && pp_process && sequence_number

    "#{pp_process.architecture_number}.#{sequence_number}"
  end

  def frequency_label(locale = I18n.locale)
    frequency.present? ? I18n.t("process_architecture.frequencies.#{frequency}", locale: locale) : nil
  end

  def automation_label(locale = I18n.locale)
    automation_status.present? ? I18n.t("process_architecture.automation.#{automation_status}", locale: locale) : nil
  end

  def service_type_label(locale = I18n.locale)
    service_type.present? ? I18n.t("pp_records.service_types.#{service_type}", locale: locale) : nil
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
    current_stage.presence || PpStage.first_key_for(record_type)
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

  # The one legal forward destination for THIS record, computed from its type.
  # nil at the end of the route.
  def next_stage_key
    PpStage.next_key(stage_key, record_type: record_type)
  end

  def route
    PpStage.route_for(record_type: record_type)
  end

  def published?
    completed?
  end

  # The head of the owning unit acts in preparation; a record with no owning
  # unit has nobody to prepare it, which the flow reports rather than hides.
  def owning_unit_head
    owner_org_unit&.head_user
  end

  def current_task
    stage_tasks.for_stage(stage_key).open.order(:assigned_at).last
  end

  # Steps in minutes, for the procedure card total.
  def computed_total_minutes
    durations = steps.filter_map(&:duration_in_minutes)
    durations.empty? ? nil : durations.sum
  end

  def computed_total_in(unit)
    minutes = computed_total_minutes
    return nil if minutes.nil?

    (minutes / PpProcessStep::MINUTES_PER_UNIT.fetch(unit.to_s, 1).to_d).round(2)
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

  # Complete when every unit in the chain has approved, by hand or by silence.
  def approvals_complete?(key = stage_key)
    scope = stage_approvals.for_stage(key)
    scope.any? && scope.where(decision: [ nil, "rejected" ]).none?
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

  def procedure_process_must_be_level_two
    return unless procedure? && pp_process
    return if pp_process.level == PpProcess::MAX_LEVEL

    errors.add(:pp_process_id, I18n.t("pp_records.errors.process_must_be_level_two"))
  end

  # A new version must say why it exists; the first issue need not.
  def reason_required_for_new_version
    return unless new_version? && TAB_TYPES.include?(record_type)
    return if change_summary.to_s.strip.present?

    errors.add(:change_summary, I18n.t("pp_records.errors.reason_required"))
  end

  # The sequence is fixed the first time the record is saved and the code is
  # built from it; both stay put after that, so a code never changes under a
  # reader's feet. A typed code is kept as typed.
  # A record starts its flow the moment it is logged.
  def enter_first_stage
    self.current_stage ||= PpStage.first_key_for(record_type)
    self.stage_entered_at ||= Time.current
  end

  def assign_code_and_sequence
    return if company.nil?

    if sequence_number.blank? && (code.blank? || new_record?)
      self.sequence_number = RecordCodeService.new(self).send(procedure? && pp_process ? :next_procedure_sequence : :next_type_sequence)
    end
    self.code = RecordCodeService.build(self) if code.blank?
  end
end
