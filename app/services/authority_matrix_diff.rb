# Compares two versions of an executive matrix and reports what changed.
#
# This replaces the "الاضافات والتعديلات" sheet, which today carries the old
# value, the new value, and a hand-set column flagging whether anything changed
# — a column that should never have to be typed, because a diff is computable.
#
# Rows are matched on the stable key an authority keeps across versions, so a
# renamed authority reads as a change rather than a deletion plus an addition.
class AuthorityMatrixDiff
  Change = Struct.new(:kind, :stable_key, :before, :after, :detail, keyword_init: true)

  def initialize(previous_matrix, current_matrix)
    @previous = previous_matrix
    @current = current_matrix
  end

  attr_reader :previous, :current

  def changes
    @changes ||= (added + removed + amended)
  end

  def any?
    changes.any?
  end

  def added
    (current_index.keys - previous_index.keys).map do |key|
      Change.new(kind: "added", stable_key: key, after: current_index[key])
    end
  end

  def removed
    (previous_index.keys - current_index.keys).map do |key|
      Change.new(kind: "removed", stable_key: key, before: previous_index[key])
    end
  end

  # An authority present in both versions whose name, basis, bands or holders
  # differ. The detail names which of those changed, which is what a reader of
  # the change table actually needs.
  def amended
    (current_index.keys & previous_index.keys).filter_map do |key|
      before = previous_index[key]
      after = current_index[key]
      differences = differing_aspects(before, after)
      next if differences.empty?

      Change.new(kind: "amended", stable_key: key, before: before, after: after, detail: differences)
    end
  end

  private

  def previous_index
    @previous_index ||= index_of(previous)
  end

  def current_index
    @current_index ||= index_of(current)
  end

  def index_of(matrix)
    return {} if matrix.nil?

    matrix.authorities.includes(bands: { assignments: :org_unit }).index_by do |authority|
      authority.stable_key.presence || "number:#{authority.number}"
    end
  end

  def differing_aspects(before, after)
    aspects = []
    aspects << "name" if before.display_name(:en) != after.display_name(:en) ||
                         before.display_name(:ar) != after.display_name(:ar)
    aspects << "basis" if before.basis_record_id != after.basis_record_id ||
                          before.basis_clause_id != after.basis_clause_id
    aspects << "bands" if band_signature(before) != band_signature(after)
    aspects << "holders" if holder_signature(before) != holder_signature(after)
    aspects
  end

  def band_signature(authority)
    authority.bands.map { |band| [ band.min_amount, band.max_amount ] }.sort_by(&:to_s)
  end

  # Who holds what, independent of row order, so reordering a matrix is not
  # reported as a change to it.
  def holder_signature(authority)
    authority.bands.flat_map do |band|
      band.assignments.map { |a| [ band.min_amount.to_s, band.max_amount.to_s, a.level, a.holder_key.to_s, a.condition.to_s ] }
    end.sort_by(&:to_s)
  end
end
