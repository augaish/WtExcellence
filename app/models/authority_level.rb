# The six levels of authority, exactly as the Executive DoA and the procedure
# authority matrix define them (خامسًا: مستويات الصلاحيات).
#
# This is CONFIGURATION, not a table: the six are fixed by the governance
# documents, so they live in code where they can be reasoned about and tested.
#
# One vocabulary is deliberately shared by three things that were separate:
#   * the Executive DoA          — who decides, at org-unit level
#   * the operational DoA        — who decides, inside a procedure
#   * the document lifecycle     — PpStage, which is an execution of a matrix
#
# Sharing it is what makes an operational matrix checkable against the
# executive one, rather than two spreadsheets someone compares by eye.
class AuthorityLevel
  DEFINITIONS = [
    { key: "prepare",   rank: 1 },
    { key: "review",    rank: 2 },
    { key: "approve",   rank: 3 },
    { key: "recommend", rank: 4 },
    { key: "authorize", rank: 5 },
    { key: "inform",    rank: 6 }
  ].freeze

  KEYS = DEFINITIONS.map { |definition| definition[:key] }.freeze

  # The final decision. Exactly one holder may carry it for a given item, which
  # is what "صاحب الصلاحية" means.
  FINAL_KEY = "authorize"

  # «لا يجوز للموظف نفسه الجمع بين مهام الإعداد والمراجعة والموافقة لنفس الإجراء»
  # — one holder must not carry all three of these on the same item. Held here
  # so the rule has a single definition rather than living in prose.
  SEGREGATED_KEYS = %w[prepare review authorize].freeze

  def self.exists?(key)
    KEYS.include?(key.to_s)
  end

  def self.rank(key)
    definition(key)&.fetch(:rank)
  end

  def self.definition(key)
    DEFINITIONS.find { |d| d[:key] == key.to_s }
  end

  def self.label(key, locale = I18n.locale)
    I18n.t("authority_levels.#{key}.label", locale: locale, default: key.to_s.humanize)
  end

  # The formal definition of the level, as written in the governance documents.
  def self.description(key, locale = I18n.locale)
    I18n.t("authority_levels.#{key}.description", locale: locale, default: "")
  end

  # A holder carrying every segregated level on one item is a conflict, whatever
  # the levels are called in the surrounding module.
  def self.segregation_conflict?(keys)
    assigned = keys.map(&:to_s).uniq
    (SEGREGATED_KEYS - assigned).empty?
  end
end
