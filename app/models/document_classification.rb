# The four confidentiality levels used on the cover of every governed document
# (تصنيف الوثيقة), with the definitions written out in the source templates.
#
# CONFIGURATION rather than a table: the four are fixed by the classification
# standard, and their definitions are quoted, not authored per company.
#
# The order runs from most to least restrictive, so `at_least_as_open_as?` can
# compare two classifications without a lookup table.
class DocumentClassification
  KEYS = %w[top_secret secret internal public].freeze

  DEFAULT_KEY = "internal"

  def self.exists?(key)
    KEYS.include?(key.to_s)
  end

  # 0 is the most restrictive. Used for comparisons, never displayed.
  def self.rank(key)
    KEYS.index(key.to_s)
  end

  def self.label(key, locale = I18n.locale)
    I18n.t("document_classifications.#{key}.label", locale: locale, default: key.to_s.humanize)
  end

  def self.description(key, locale = I18n.locale)
    I18n.t("document_classifications.#{key}.description", locale: locale, default: "")
  end

  # Options for a select, in order.
  def self.options(locale = I18n.locale)
    KEYS.map { |key| [ label(key, locale), key ] }
  end

  # Public documents are the only ones that may leave the company, which is what
  # the Trust Center publishes.
  def self.publishable?(key)
    key.to_s == "public"
  end
end
