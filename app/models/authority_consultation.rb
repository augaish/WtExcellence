# One objection raised by an organizational unit against a draft matrix, and
# Institutional Excellence's ruling on it.
#
# This is the cycle run in a spreadsheet today — 172 rows of challenge,
# proposal, expected impact and ruling, with a manual column flagging whether
# anything changed as a result. Here the trail from objection to ruling is the
# record itself.
class AuthorityConsultation < ApplicationRecord
  belongs_to :matrix, class_name: "PpRecord"
  belongs_to :authority, optional: true
  belongs_to :org_unit, optional: true
  belongs_to :raised_by, class_name: "User", optional: true
  belongs_to :ruled_by, class_name: "User", optional: true

  # open      — raised, not yet ruled on
  # accepted  — the objection is upheld and the matrix changes
  # rejected  — the objection is not upheld
  # deferred  — operational detail, to be handled in the procedure rather than
  #             the executive matrix (the most common ruling in the source sheet)
  STATUSES = %w[open accepted rejected deferred].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :challenge, presence: true
  # A ruling must say something. An objection dismissed without a reason is how
  # a consultation stops being one.
  validates :ruling, presence: true, if: :ruled?

  scope :open_items, -> { where(status: "open") }
  scope :ruled, -> { where.not(status: "open") }
  scope :ordered, -> { order(:created_at) }

  before_save :stamp_ruling

  def ruled?
    status != "open"
  end

  def status_label(locale = I18n.locale)
    I18n.t("doa.consultation.statuses.#{status}", locale: locale)
  end

  private

  def stamp_ruling
    return unless status_changed?

    if ruled?
      self.ruled_at = Time.current
      self.ruled_by ||= Thread.current[:current_user]
    else
      self.ruled_at = nil
      self.ruled_by = nil
    end
  end
end
