# Words for the Activity page and the History box on a record.
module ActivityHelper
  # "Policy record created", or the app's own description for actions that
  # are not a plain create, update or delete.
  def activity_entry_label(entry)
    verb, entity = ActivityCatalogue.split_action(entry.action)
    return activity_action_label(entry) if verb.nil?

    t("activity.verbs.#{verb}", record: activity_entity_label(entity))
  end

  def activity_entity_label(entity_type)
    t("activity.entities.#{entity_type}", default: entity_type.to_s.humanize)
  end

  def activity_module_label(entity_type)
    t("activity.modules.#{ActivityCatalogue.module_for(entity_type)}")
  end
end
