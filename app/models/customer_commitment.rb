class CustomerCommitment < ApplicationRecord
  include GovernanceCapaLinkable
  include GovernanceActivity

  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :uploads, through: :evidence_attachments

  tracks_governance_activity entity: "customer_commitment",
    tracks: %i[status due_date owner_id fulfillment_note acceptance_status delivered_on],
    summary: %i[title customer_name due_date]

  belongs_to :company
  belongs_to :owner, class_name: "CompanyUser", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :fulfilled_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :vendor, optional: true
  belongs_to :recurred_from, class_name: "CustomerCommitment", optional: true

  # Whether the customer accepted what was delivered: separate from our own
  # "fulfilled", because those two views can disagree.
  ACCEPTANCE_STATUSES = %w[pending accepted rejected].freeze
  RECURRENCES = %w[none monthly quarterly annual].freeze

  # Workflow state: where the work has got to. Timing — whether it is late — is
  # derived from the due date and never chosen, so an obligation cannot be
  # marked Overdue while on time or sit at Open weeks past its date.
  enum :status, {
    open: "open",
    in_progress: "in_progress",
    fulfilled: "fulfilled"
  }, default: "open"

  # How the obligation stands against its due date, independent of the workflow
  # state. Both are shown, because "In progress / 4 days overdue" says something
  # neither half says alone.
  TIMING_STATES = %w[no_due_date not_due due_soon overdue fulfilled_on_time fulfilled_late].freeze

  DUE_SOON_DAYS = 30

  validates :title, presence: true
  validates :customer_name, presence: true
  validates :acceptance_status, inclusion: { in: ACCEPTANCE_STATUSES }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :agreement_reference, length: { maximum: 250 }
  validates :acceptance_criteria, :acceptance_note, length: { maximum: 5000 }
  validate :vendor_must_be_same_company

  # Fulfilment is a governance decision: it must say on what basis the
  # obligation was accepted as met, the same way closing a risk must.
  validates :fulfillment_note, presence: true, if: :fulfillment_note_required?

  before_save :stamp_fulfillment
  after_save :schedule_next_occurrence

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :due_soon, -> { active.where(due_date: Date.current..DUE_SOON_DAYS.days.from_now).where.not(status: "fulfilled") }
  scope :past_due, -> { active.where(due_date: ...Date.current).where.not(status: "fulfilled") }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def past_due?(on = Date.current)
    due_date.present? && due_date < on && !fulfilled?
  end

  def timing_state(on = Date.current)
    return fulfilled_timing if fulfilled?
    return "no_due_date" if due_date.blank?
    return "overdue" if due_date < on
    return "due_soon" if due_date <= on + DUE_SOON_DAYS.days

    "not_due"
  end

  def timing_label(on = Date.current, locale = I18n.locale)
    I18n.t("commitment_timing.timing.#{timing_state(on)}", locale: locale)
  end

  # Days past the due date, for the "4 days overdue" half of the label.
  def days_overdue(on = Date.current)
    reference = fulfilled? ? fulfilled_at&.to_date : on
    return 0 if due_date.blank? || reference.nil? || reference <= due_date

    (reference - due_date).to_i
  end

  def fulfilled_late?
    fulfilled? && due_date.present? && fulfilled_at.present? && fulfilled_at.to_date > due_date
  end

  def recurrence_label(locale = I18n.locale)
    I18n.t("commitment_depth.recurrences.#{recurrence}", locale: locale)
  end

  def acceptance_label(locale = I18n.locale)
    I18n.t("commitment_depth.acceptance_statuses.#{acceptance_status}", locale: locale)
  end

  # The customer's verdict, recorded by whoever verified it.
  def record_acceptance!(status, by:, note: nil)
    update!(acceptance_status: status, verified_by: by, acceptance_note: note.presence)
  end

  def next_due_date
    return nil if due_date.blank? || recurrence == "none"

    case recurrence
    when "monthly" then due_date + 1.month
    when "quarterly" then due_date + 3.months
    when "annual" then due_date + 1.year
    end
  end

  private

  def vendor_must_be_same_company
    return if vendor.nil? || vendor.company_id == company_id

    errors.add(:vendor_id, I18n.t("commitment_depth.errors.vendor_other_company"))
  end

  # A recurring obligation, once fulfilled, opens the next occurrence with the
  # next due date so the register never goes quiet on a standing promise.
  def schedule_next_occurrence
    return unless saved_change_to_status? && fulfilled? && recurrence != "none" && next_due_date
    return if CustomerCommitment.exists?(recurred_from_id: id)

    CustomerCommitment.create!(
      company: company, title: title, description: description, customer_name: customer_name,
      agreement_reference: agreement_reference, acceptance_criteria: acceptance_criteria, vendor: vendor,
      owner: owner, created_by: created_by, due_date: next_due_date, recurrence: recurrence, recurred_from: self
    )
  end

  # A fulfilment made or changed now needs a basis; obligations fulfilled before
  # the requirement existed keep a null note until someone touches their status.
  def fulfillment_note_required?
    fulfilled? && (new_record? || status_changed? || fulfillment_note_changed?)
  end

  def fulfilled_timing
    return "fulfilled_late" if fulfilled_late?

    "fulfilled_on_time"
  end

  # Completion time is stamped by the system, never typed, so "fulfilled late"
  # cannot be edited away.
  def stamp_fulfillment
    return unless status_changed?

    if fulfilled?
      self.fulfilled_at = Time.current
      self.fulfilled_by ||= Thread.current[:current_user]
    else
      self.fulfilled_at = nil
      self.fulfilled_by = nil
      self.fulfillment_note = nil
    end
  end
end
