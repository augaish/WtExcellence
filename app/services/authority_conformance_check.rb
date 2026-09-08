# Checks a procedure's operational authority matrix against the executive one.
#
# The source documents require this in words: units detail their operational
# decisions «بما يتماشى مع الصلاحيات التنفيذية المحددة في هذه المصفوفة
# وبالتنسيق مع الإدارة العامة للتميز المؤسسي». Today that coordination is a
# person comparing two spreadsheets. This computes it.
#
# What conformance means here, concretely: an operational decision that
# exercises an executive authority must not place final authorization at a
# LOWER organizational level than the executive matrix does. Pushing a decision
# down the hierarchy is how authority quietly escapes the org chart; pushing it
# up is always permitted, since «أي صلاحية مفوضة لمسؤول يمكن ممارستها من
# المسؤول الأعلى له».
class AuthorityConformanceCheck
  Finding = Struct.new(:operational, :authority, :kind, :detail, keyword_init: true) do
    def message(locale = I18n.locale)
      I18n.t("doa.conformance.#{kind}", locale: locale, **(detail || {}))
    end
  end

  def initialize(process)
    @process = process
  end

  attr_reader :process

  def findings
    @findings ||= operational_authorities.flat_map { |row| findings_for(row) }
  end

  def any?
    findings.any?
  end

  # Rows that claim to exercise an executive authority. A row with no link is
  # not a breach: an operational matrix legitimately covers decisions the
  # executive matrix never mentions.
  def linked_rows
    operational_authorities.select(&:authority)
  end

  private

  def operational_authorities
    @operational_authorities ||=
      process.authorities.includes(:assignments, authority: { bands: { assignments: :org_unit } }).to_a
  end

  def findings_for(operational)
    authority = operational.authority
    return [] if authority.nil?

    executive_level = highest_executive_authorizer_level(authority)
    return [ unresolved_finding(operational, authority) ] if executive_level.nil?

    operational_level = lowest_operational_authorizer_level(operational)
    return [] if operational_level.nil?

    # A larger level number is further down the hierarchy.
    return [] if operational_level <= executive_level

    [ Finding.new(
      operational: operational,
      authority: authority,
      kind: "authorizes_below_executive",
      detail: { operational_level: operational_level, executive_level: executive_level }
    ) ]
  end

  # The executive matrix may place authorization differently per band; the
  # highest-placed authorizer is the one an operational row must not undercut.
  def highest_executive_authorizer_level(authority)
    levels = authority.bands.flat_map do |band|
      band.assignments.select { |a| a.level == AuthorityLevel::FINAL_KEY }.filter_map { |a| a.org_unit&.level }
    end

    levels.min
  end

  def lowest_operational_authorizer_level(operational)
    levels = operational.assignments
      .select { |assignment| assignment.level == AuthorityLevel::FINAL_KEY }
      .filter_map { |assignment| assignment.org_unit&.level }

    levels.max
  end

  # An executive authority whose authorizer is a dynamic role or a written
  # position cannot be compared by level. Reported rather than passed silently:
  # an unresolvable holder is itself the finding.
  def unresolved_finding(operational, authority)
    Finding.new(operational: operational, authority: authority, kind: "executive_unresolvable")
  end
end
