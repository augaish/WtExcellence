# The findings a matrix version carries: the things an auditor opens the file to
# check, computed instead of read off 202 rows by eye.
#
# Deliberately advisory. A matrix is populated over weeks, and blocking a save
# because a half-entered authority has no authorizer yet would make the register
# unusable — the findings are what the company works through, not a gate.
class AuthorityMatrixReport
  Finding = Struct.new(:authority, :band, :kind, keyword_init: true) do
    def message(locale = I18n.locale)
      I18n.t("doa.findings.#{kind}", locale: locale)
    end
  end

  def initialize(matrix)
    @matrix = matrix
  end

  attr_reader :matrix

  def authorities
    @authorities ||= matrix.authorities.includes(:authority_category, bands: { assignments: :org_unit }).to_a
  end

  def findings
    @findings ||= authorities.flat_map { |authority| findings_for(authority) }
  end

  def any?
    findings.any?
  end

  # Findings for one authority, so the matrix can show them beside their row.
  def findings_for(authority)
    found = []

    authority.bands.each do |band|
      if band.authorizers.empty?
        found << Finding.new(authority: authority, band: band, kind: "no_authorizer")
      elsif band.authorizers.size > 1
        found << Finding.new(authority: authority, band: band, kind: "many_authorizers")
      end

      found << Finding.new(authority: authority, band: band, kind: "segregation") if band.segregation_breaches.any?
    end

    found
  end

  # Grouped for display, so a category with no findings stays quiet.
  def by_authority
    findings.group_by(&:authority)
  end
end
