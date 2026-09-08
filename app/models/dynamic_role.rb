# The fix for the weakest part of the source matrix.
#
# Its column headers are prose — "الوكيل المعني", "وكلاء الوكالات المعنية",
# "مدراء الجهات المعنية" — "the concerned X". At audit time nobody can prove who
# that was on a given decision. A dynamic role names the rule instead of the
# post, so the system can resolve it against the org structure and record the
# unit it actually meant.
#
# CONFIGURATION rather than a table: each role needs a resolver written for it,
# so the set is fixed by the code that can resolve it.
class DynamicRole
  KEYS = %w[owning_unit parent_unit direct_manager concerned_unit].freeze

  def self.exists?(key)
    KEYS.include?(key.to_s)
  end

  def self.label(key, locale = I18n.locale)
    I18n.t("doa.dynamic_roles.#{key}.label", locale: locale, default: key.to_s.humanize)
  end

  # How the role is resolved, stated plainly, because a rule nobody can read is
  # no better than the prose it replaced.
  def self.rule(key, locale = I18n.locale)
    I18n.t("doa.dynamic_roles.#{key}.rule", locale: locale, default: "")
  end

  def self.options(locale = I18n.locale)
    KEYS.map { |key| [ label(key, locale), key ] }
  end

  # Resolves the role against a subject unit. Returns nil when the org structure
  # cannot answer, which is itself worth reporting: an authority whose holder
  # cannot be resolved is an audit finding, not a blank cell.
  def self.resolve(key, subject_unit)
    return nil if subject_unit.nil?

    case key.to_s
    when "owning_unit", "concerned_unit" then subject_unit
    when "parent_unit" then subject_unit.parent
    when "direct_manager" then subject_unit.parent || subject_unit
    end
  end
end
