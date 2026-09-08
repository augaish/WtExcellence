module GovernanceActivityHelper
  # One line of history, in words rather than as a payload dump.
  #
  # An audit trail is only useful if a reader can tell what happened without
  # knowing the column names, so values are rendered the way the record shows
  # them and a blank becomes "not set" rather than an empty gap.
  def activity_change_sentences(entry)
    changes = entry.payload_json&.dig("changes")
    return [] if changes.blank?

    changes.map do |attribute, (before, after)|
      t("governance_activity.change",
        attribute: activity_attribute_label(entry.entity_type, attribute),
        from: activity_value(before),
        to: activity_value(after))
    end
  end

  def activity_action_label(entry)
    t("governance_activity.actions.#{entry.action.downcase}", default: entry.action.humanize)
  end

  private

  def activity_attribute_label(entity_type, attribute)
    t("governance_activity.attributes.#{attribute}",
      default: t("activerecord.attributes.#{entity_type}.#{attribute}", default: attribute.humanize))
  end

  def activity_value(value)
    return t("governance_activity.not_set") if value.nil? || value.to_s.strip.empty?
    return l(value.to_date, format: :long) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    value.to_s.truncate(80)
  end
end
