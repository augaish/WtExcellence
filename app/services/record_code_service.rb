# Builds a record's code the way the product owner spelled it out:
#
#   TYPE-UNIT-NUMBER-Vn        e.g. POL-HR-001-V1
#   PROC-UNIT-A.B.C.n-Vn       e.g. PROC-HR-1.2.4.12-V1
#
# TYPE is fixed per record type. UNIT is the owning unit's code, or the
# initials of its English name when it has no code. NUMBER is the next free
# sequence for that type and unit; a procedure instead takes its level-2
# process's architecture number plus its own sequence within that process.
# Vn is the version, so a new version keeps the base and only moves the tail.
class RecordCodeService
  PREFIXES = {
    "policy" => "POL", "procedure" => "PROC", "form" => "FRM", "service" => "SEV", "glossary" => "GLO",
    "work_instruction" => "WI", "guideline" => "GDL", "charter" => "CHR",
    "executive_doa" => "EDOA", "operational_doa" => "ODOA", "sla" => "SLA"
  }.freeze

  VERSION_TAIL = /-V\d+\z/

  def self.build(record)
    new(record).build
  end

  # The same base with the version moved on: POL-HR-001-V1 -> POL-HR-001-V2.
  def self.next_version_code(code, version_number)
    return nil if code.blank?

    "#{code.sub(VERSION_TAIL, '')}-V#{version_number}"
  end

  def initialize(record)
    @record = record
  end

  def build
    [ prefix, unit_part, number_part, "V#{record.version_number.to_i.nonzero? || 1}" ].compact.join("-")
  end

  private

  attr_reader :record

  def prefix
    PREFIXES.fetch(record.record_type.to_s, "REC")
  end

  def unit_part
    unit = record.owner_org_unit
    return "GEN" if unit.nil?

    unit.code.presence || initials(unit.name_en) || "GEN"
  end

  def initials(name)
    letters = name.to_s.split(/[\s\-\/&]+/).map { |w| w[0] }.compact.join.upcase
    letters.presence&.first(4)
  end

  def number_part
    if record.record_type == "procedure" && record.pp_process
      "#{record.pp_process.architecture_number}.#{record.sequence_number || next_procedure_sequence}"
    else
      format("%03d", record.sequence_number || next_type_sequence)
    end
  end

  # Sequence within the level-2 process, counted over every version so a
  # re-issued procedure never takes a fresh number.
  def next_procedure_sequence
    siblings = record.company.pp_records.of_type("procedure").where(pp_process_id: record.pp_process_id)
    siblings = siblings.where.not(id: record.id) if record.persisted?
    siblings.maximum(:sequence_number).to_i + 1
  end

  def next_type_sequence
    siblings = record.company.pp_records.of_type(record.record_type)
      .where(owner_org_unit_id: record.owner_org_unit_id)
    siblings = siblings.where.not(id: record.id) if record.persisted?
    siblings.maximum(:sequence_number).to_i + 1
  end
end
