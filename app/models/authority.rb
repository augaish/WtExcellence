# One power to decide something, within a version of the executive matrix.
#
# It belongs to the executive_doa record that governs it, so two versions can
# coexist and be compared — which is what replaces the "الاضافات والتعديلات"
# sheet maintained by hand today.
class Authority < ApplicationRecord
  belongs_to :company
  belongs_to :matrix, class_name: "PpRecord"
  belongs_to :authority_category, optional: true
  belongs_to :basis_record, class_name: "PpRecord", optional: true
  belongs_to :basis_clause, class_name: "Clause", optional: true

  has_many :bands, -> { ordered }, class_name: "AuthorityBand", dependent: :destroy
  has_many :delegations, class_name: "AuthorityDelegation", dependent: :destroy
  # Operational decisions that say they exercise this authority keep their row
  # and lose the link when the authority goes.
  has_many :operational_uses, class_name: "PpProcessAuthority", foreign_key: "authority_id", dependent: :nullify
  has_many :consultations, class_name: "AuthorityConsultation", foreign_key: "authority_id", dependent: :nullify
  has_many :review_comments, -> { ordered }, class_name: "AuthorityReviewComment", dependent: :destroy
  has_many :assignments, through: :bands

  validates :name_en, length: { maximum: 500 }
  validates :name_ar, length: { maximum: 500 }
  validate :must_have_a_name
  validate :matrix_must_be_an_executive_doa
  validate :matrix_must_be_editable

  scope :ordered, -> { order(:sort_order, :number, :created_at) }

  # Numbers as printed: the category number, a dot, the position inside the
  # category (1.1, 1.2, 2.1 …). Uncategorised rows count from 0. Computed from
  # the order the rows sit in, so dragging renumbers without a save per row.
  def self.numbered(authorities)
    numbers = {}
    authorities.group_by(&:authority_category).each do |category, rows|
      rows.each_with_index { |authority, i| numbers[authority.id] = "#{category&.number || 0}.#{i + 1}" }
    end
    numbers
  end
  scope :in_category, ->(category) { where(authority_category_id: category&.id) }
  scope :without_basis, -> { where(basis_record_id: nil, basis_clause_id: nil) }

  before_validation :assign_stable_key, on: :create
  after_create :ensure_default_band

  def display_name(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ name_ar, name_en ] : [ name_en, name_ar ]
    primary.presence || fallback.presence || ""
  end

  # True when the authority is split by money or volume thresholds rather than
  # holding one unbounded band. Bands are no longer offered on the page; every
  # authority keeps one default band that its holders hang off.
  def banded?
    bands.size > 1 || bands.any?(&:bounded?)
  end

  # The one band holders are written into now that thresholds are text.
  def default_band
    bands.first || bands.create!
  end

  # A delegated holder is shown in the matrix in a different colour; this
  # gathers the delegations in force so the page can mark them.
  def delegations_in_force
    delegations.select(&:in_force?)
  end

  # An authority nobody may finally authorize cannot be exercised; one with two
  # authorizers in the same band leaves nobody knowing who decides. Returns the
  # bands in question so the matrix can point at them.
  def bands_without_single_authorizer
    bands.reject(&:single_authorizer?)
  end

  def segregation_breaches
    bands.flat_map(&:segregation_breaches).uniq
  end

  # The regulation the authority derives from. Every row of an audited matrix
  # should be able to answer this.
  def basis_label(locale = I18n.locale)
    return basis_record.display_title(locale) if basis_record

    return nil if basis_clause.nil?

    [ basis_clause.full_code, basis_clause.title(locale.to_s) ].compact_blank.join(" — ")
  end

  private

  # An authority carries one identity across matrix versions, so a diff can tell
  # a renamed row from a deleted one. A clone copies the key rather than
  # generating a new one.
  def assign_stable_key
    self.stable_key = SecureRandom.hex(8) if stable_key.blank?
  end

  # An authority with no thresholds still needs somewhere to hang its holders,
  # so it gets one unbounded band rather than a special case everywhere else.
  def ensure_default_band
    bands.create! if bands.empty?
  end

  def must_have_a_name
    return if name_en.present? || name_ar.present?

    errors.add(:base, I18n.t("doa.errors.authority_name_required"))
  end

  def matrix_must_be_an_executive_doa
    return if matrix.nil? || matrix.record_type == "executive_doa"

    errors.add(:matrix, I18n.t("doa.errors.matrix_wrong_type"))
  end

  def published_matrix_for_guard
    matrix
  end

  # A matrix that has been published is a statement of record. Changing an
  # authority in it would change what was approved without anyone approving
  # the change; the next version is where edits belong.
  def matrix_must_be_editable
    m = published_matrix_for_guard
    return if m.nil? || !m.completed?

    errors.add(:base, I18n.t("doa.errors.matrix_published"))
  end
end
