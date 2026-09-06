# Generates hierarchical codes for tree records (org units, processes).
#
#   root:  "01", "02", ...            (processes are prefixed: "P-01")
#   child: "<parent code>-01", "<parent code>-02", ...
#
# Codes are a convenience, not an identity: the user may override any code, and
# a manual code is never renumbered. Uniqueness is enforced by the model.
class HierarchicalCodeService
  PROCESS_PREFIX = "P-".freeze

  # One prefix per record type, so a code reads at a glance (POL-01, PRO-03).
  RECORD_PREFIXES = {
    "policy" => "POL-", "procedure" => "PRO-", "work_instruction" => "WI-",
    "form" => "FRM-", "service" => "SVC-", "guideline" => "GDL-", "charter" => "CHR-"
  }.freeze

  def self.next_org_unit_code(company:, parent: nil)
    new(scope: company.org_units, parent: parent).next_code
  end

  def self.next_process_code(company:, parent: nil)
    new(scope: company.pp_processes, parent: parent, root_prefix: PROCESS_PREFIX).next_code
  end

  def self.next_record_code(company:, record_type:)
    prefix = RECORD_PREFIXES.fetch(record_type.to_s, "REC-")
    new(scope: company.pp_records, root_prefix: prefix).next_code
  end

  def initialize(scope:, parent: nil, root_prefix: "")
    @scope = scope
    @parent = parent
    @root_prefix = root_prefix
  end

  def next_code
    # Flat scopes (records) have no parent_id column; tree scopes number within
    # their sibling set.
    siblings = if @scope.klass.column_names.include?("parent_id")
      @parent ? @scope.where(parent_id: @parent.id) : @scope.where(parent_id: nil)
    else
      @scope
    end
    used = siblings.pluck(:code).compact

    prefix = if @parent&.code.present?
      "#{@parent.code}-"
    else
      @root_prefix
    end

    highest = used.filter_map do |code|
      next unless code.start_with?(prefix)

      tail = code.delete_prefix(prefix)
      tail.match?(/\A\d+\z/) ? tail.to_i : nil
    end.max || 0

    candidate = nil
    (highest + 1).upto(highest + 1000) do |n|
      candidate = format("%s%02d", prefix, n)
      break unless @scope.exists?(code: candidate)
    end
    candidate
  end
end
