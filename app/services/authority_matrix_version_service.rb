# Opens a new version of an executive matrix by copying the current one.
#
# A new version is a copy rather than an edit in place, so the approved version
# stays exactly as approved while the next one is worked on and consulted over —
# and so the two can be diffed. Authorities keep their stable key, which is what
# makes the diff able to tell a renamed row from a replaced one.
class AuthorityMatrixVersionService
  def self.open_next(matrix, actor: nil)
    new(matrix, actor: actor).open_next
  end

  # The page starts empty. The first category (or the first pick from the
  # catalogue) creates version 1 of the company's executive matrix. Categories
  # left behind by a matrix that was deleted would otherwise reappear beside
  # the first new one, so a fresh start clears them.
  def self.first_version(company, actor: nil)
    company.authority_categories.destroy_all
    company.pp_records.create!(
      record_type: "executive_doa",
      title_en: I18n.t("doa.matrix", locale: :en),
      title_ar: I18n.t("doa.matrix", locale: :ar),
      owner_user: actor,
      version_number: 1,
      version_label: "v1"
    )
  end

  def initialize(matrix, actor: nil)
    @matrix = matrix
    @actor = actor
  end

  attr_reader :matrix, :actor

  def open_next
    ActiveRecord::Base.transaction do
      successor = build_successor
      matrix.authorities.includes(bands: :assignments).each { |authority| copy_authority(authority, successor) }
      successor
    end
  end

  private

  def build_successor
    matrix.company.pp_records.create!(
      record_type: "executive_doa",
      title_en: matrix.title_en,
      title_ar: matrix.title_ar,
      description: matrix.description,
      classification: matrix.classification,
      owner_user: matrix.owner_user,
      owner_org_unit: matrix.owner_org_unit,
      previous_version: matrix,
      version_number: matrix.version_number + 1,
      version_label: next_version_label,
      current_stage: PpStage::KEYS.first,
      stage_entered_at: Time.current
    )
  end

  # "v2" follows "v1"; anything a company has written by hand is left alone and
  # the number is used instead.
  def next_version_label
    match = matrix.version_label.to_s.match(/\Av(\d+)\z/i)
    return "v#{match[1].to_i + 1}" if match

    "v#{matrix.version_number + 1}"
  end

  def copy_authority(authority, successor)
    copy = successor.authorities.create!(
      company: authority.company,
      authority_category: authority.authority_category,
      number: authority.number,
      name_en: authority.name_en,
      name_ar: authority.name_ar,
      notes: authority.notes,
      basis_record: authority.basis_record,
      basis_clause: authority.basis_clause,
      conflict_sensitive: authority.conflict_sensitive,
      sort_order: authority.sort_order,
      stable_key: authority.stable_key
    )

    # The copy is created with one default band; the originals replace it.
    copy.bands.destroy_all
    authority.bands.each { |band| copy_band(band, copy) }
  end

  def copy_band(band, copy)
    new_band = copy.bands.create!(
      label_en: band.label_en, label_ar: band.label_ar,
      min_amount: band.min_amount, max_amount: band.max_amount, sort_order: band.sort_order
    )

    band.assignments.each do |assignment|
      new_band.assignments.create!(
        level: assignment.level, org_unit_id: assignment.org_unit_id,
        dynamic_role: assignment.dynamic_role, holder_title: assignment.holder_title,
        condition: assignment.condition, sort_order: assignment.sort_order
      )
    end
  end
end
