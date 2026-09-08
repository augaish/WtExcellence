# Suggested starting points for a company building its own authority matrix.
#
# These are SUGGESTIONS, never seeded data. A delegation matrix states who may
# decide what in a particular organisation; one imported wholesale from another
# body would be wrong in ways nobody would notice until it mattered. So nothing
# here is created unless a company asks for it, everything created is ordinary
# editable data, and every suggestion is generic rather than lifted from any
# organisation's approved matrix.
#
# CONFIGURATION rather than a table: the list is a starting point maintained
# with the product, not company data.
class AuthorityCatalogue
  # Categories common to most governance matrices, in the order they usually
  # appear. A company keeps the ones that fit and deletes the rest.
  CATEGORIES = [
    { key: "general",        authorities: %w[general_agreements general_studies] },
    { key: "governance",     authorities: %w[governance_framework risk_reports continuity_plan] },
    { key: "committees",     authorities: %w[committee_formation committee_membership] },
    { key: "legal",          authorities: %w[internal_regulations legal_representation contract_review] },
    { key: "internal_audit", authorities: %w[audit_plan audit_reports] },
    { key: "strategy",       authorities: %w[strategic_plan new_projects] },
    { key: "excellence",     authorities: %w[policies_and_procedures org_structure] },
    { key: "financial",      authorities: %w[budget budget_transfers advances] },
    { key: "human_capital",  authorities: %w[recruitment training_plan leave_and_secondment] },
    { key: "procurement",    authorities: %w[direct_purchase contract_award contract_signature] },
    { key: "administrative", authorities: %w[asset_disposal facilities information_security] },
    { key: "communications", authorities: %w[media_statements campaigns] },
    { key: "partnerships",   authorities: %w[memoranda_of_understanding international_membership] }
  ].freeze

  def self.categories(locale = I18n.locale)
    CATEGORIES.map do |entry|
      {
        key: entry[:key],
        name: category_name(entry[:key], locale),
        authorities: entry[:authorities].map { |key| { key: key, name: authority_name(key, locale) } }
      }
    end
  end

  def self.category_name(key, locale = I18n.locale)
    I18n.t("doa.catalogue.categories.#{key}", locale: locale, default: key.to_s.humanize)
  end

  def self.authority_name(key, locale = I18n.locale)
    I18n.t("doa.catalogue.authorities.#{key}", locale: locale, default: key.to_s.humanize)
  end

  # Creates the chosen suggestions as ordinary records the company then owns.
  #
  # Categories already present by name are reused rather than duplicated, so
  # asking twice does not produce two "Financial" categories. Nothing is
  # assigned a holder: who decides is the company's judgement, not ours, and a
  # suggested holder would be the one part of a matrix that must never be
  # guessed.
  def self.apply(matrix, category_keys:, locale: I18n.locale)
    company = matrix.company
    created = { categories: 0, authorities: 0 }

    CATEGORIES.select { |entry| category_keys.map(&:to_s).include?(entry[:key]) }.each do |entry|
      name = category_name(entry[:key], locale)
      category = company.authority_categories.find_by(name_en: category_name(entry[:key], :en))

      if category.nil?
        category = company.authority_categories.create!(
          name_en: category_name(entry[:key], :en),
          name_ar: category_name(entry[:key], :ar),
          sort_order: company.authority_categories.maximum(:sort_order).to_i + 1
        )
        created[:categories] += 1
      end

      entry[:authorities].each do |authority_key|
        next if matrix.authorities.exists?(name_en: authority_name(authority_key, :en))

        company.authorities.create!(
          matrix: matrix,
          authority_category: category,
          name_en: authority_name(authority_key, :en),
          name_ar: authority_name(authority_key, :ar),
          number: matrix.authorities.maximum(:number).to_i + 1,
          sort_order: matrix.authorities.maximum(:sort_order).to_i + 1
        )
        created[:authorities] += 1
      end
    end

    created
  end
end
