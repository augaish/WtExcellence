class PpRecord < ApplicationRecord
  # Governed content types.
  TYPES = %w[policy procedure work_instruction form service guideline charter].freeze

  # Types that document how work is carried out must hang off a process; the
  # enterprise-wide types may stand alone.
  PROCESS_REQUIRED_TYPES = %w[procedure work_instruction form].freeze

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

  validates :record_type, presence: true, inclusion: { in: TYPES }
  validates :code, length: { maximum: 50 }, allow_blank: true
  validates :code, uniqueness: { scope: :company_id }, allow_blank: true
  validates :title_en, length: { maximum: 300 }
  validates :title_ar, length: { maximum: 300 }
  validates :version_label, length: { maximum: 50 }, allow_blank: true
  validate :must_have_a_title
  validate :package_must_be_same_company
  validate :process_must_be_same_company
  validate :review_after_effective

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:record_type, :code, :created_at) }
  scope :of_type, ->(type) { where(record_type: type) }
  scope :unpackaged, -> { where(package_id: nil) }
  scope :in_package, ->(package) { where(package_id: package.id) }
  scope :due_for_review, ->(on = Date.current) { where(review_date: ..on) }

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
end
