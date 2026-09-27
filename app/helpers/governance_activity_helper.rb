module GovernanceActivityHelper
  # One line of history, in words rather than as a payload dump.
  #
  # An audit trail is only useful if a reader can tell what happened without
  # knowing the column names or the ids behind them: a changed owner is shown
  # by name, a status by its label, a blank as "not set".
  def activity_change_sentences(entry)
    changes = entry.payload_json&.dig("changes")
    return [] if changes.blank?

    changes.map do |attribute, (before, after)|
      t("governance_activity.change",
        attribute: activity_attribute_label(entry.entity_type, attribute),
        from: activity_value(before, entity_type: entry.entity_type, attribute: attribute),
        to: activity_value(after, entity_type: entry.entity_type, attribute: attribute))
    end
  end

  def activity_action_label(entry)
    t("governance_activity.actions.#{entry.action.downcase}", default: entry.action.humanize)
  end

  private

  def activity_attribute_label(entity_type, attribute)
    name = attribute.to_s.sub(/_id\z/, "")
    t("governance_activity.attributes.#{attribute}",
      default: t("activerecord.attributes.#{entity_type}.#{attribute}",
        default: t("activerecord.attributes.#{entity_type}.#{name}", default: name.humanize)))
  end

  def activity_value(value, entity_type: nil, attribute: nil)
    return t("governance_activity.not_set") if value.nil? || value.to_s.strip.empty?
    return l(value.to_date, format: :long) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    model = activity_model(entity_type)
    if model && attribute
      named = activity_reference_name(model, attribute, value)
      return named if named
      label = activity_enum_label(model, attribute, value)
      return label if label
    end
    value.to_s.truncate(80)
  end

  def activity_model(entity_type)
    entity_type.to_s.classify.safe_constantize
  rescue NameError
    nil
  end

  # A foreign key becomes the name of the record it points at: the person for
  # a membership, otherwise whatever the record calls itself.
  def activity_reference_name(model, attribute, value)
    return nil unless attribute.to_s.end_with?("_id")

    association = model.reflect_on_all_associations(:belongs_to).find { |a| a.foreign_key.to_s == attribute.to_s }
    return nil if association.nil? || association.polymorphic?

    target = association.klass.find_by(id: value)
    return t("governance_activity.removed_record") if target.nil?
    return target.user&.name.presence || target.id if target.is_a?(CompanyUser)

    target.respond_to?(:activity_label) ? target.activity_label : target.to_s
  end

  # A stored key becomes its label: the model's enum translation when there is
  # one, the module's own status lists otherwise, a readable word at worst.
  def activity_enum_label(model, attribute, value)
    key = value.to_s
    candidates = [
      "activerecord.attributes.#{model.model_name.i18n_key}.#{attribute.to_s.pluralize}.#{key}",
      "#{model.model_name.i18n_key}_depth.#{attribute.to_s.pluralize}.#{key}",
      "vendor_assessment.#{attribute.to_s.pluralize}.#{key}",
      "commitment_depth.#{attribute.to_s.pluralize}.#{key}",
      "risk_depth.#{attribute.to_s.pluralize}.#{key}",
      "risk_level_#{key}",
      "capa_actions.statuses.#{key}",
      "capa_management_ui.statuses.#{key}"
    ]
    found = candidates.find { |c| I18n.exists?(c) }
    return t(found) if found

    enum_backed = model.respond_to?(:defined_enums) && model.defined_enums.key?(attribute.to_s)
    return key.humanize if enum_backed || attribute.to_s.match?(/status|level|kind|type|strategy|source|mode|frequency|criticality/)

    nil
  end
end
