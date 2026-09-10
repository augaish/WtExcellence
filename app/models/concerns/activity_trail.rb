# Every record leaves a trace: who created, changed or deleted it, when, and
# which fields went from what to what. On by default for every model; a
# model that is noise rather than record (caches, notifications, layouts)
# opts out with `skip_activity_trail`.
#
# Entries are written to the audit log with the actor from the request. A
# background job touching a record writes nothing rather than an anonymous
# entry. The company is taken from the record, or from the first parent that
# has one, so a clause on a policy is filed under the policy's company.
#
# Risks, vendors and commitments keep their own richer create/update trail
# (GovernanceActivity); this concern adds only their deletion.
module ActivityTrail
  extend ActiveSupport::Concern

  # Never stored, whatever the model.
  SECRET_ATTRIBUTES = /password|token|digest|secret|api_key|otp/i
  # Change noise, not change.
  QUIET_ATTRIBUTES = %w[id created_at updated_at lock_version].freeze

  included do
    class_attribute :activity_trail_enabled, instance_writer: false, default: true

    after_create :write_activity_creation
    after_update :write_activity_update
    after_destroy :write_activity_deletion
  end

  class_methods do
    def skip_activity_trail
      self.activity_trail_enabled = false
    end

    def activity_entity_type
      model_name.param_key
    end
  end

  # The record's own history, newest first.
  def activity_trail(limit: 50)
    AuditLog.where(entity_type: self.class.activity_entity_type, entity_id: id).order(created_at: :desc).limit(limit)
  end

  # What the entry calls the record: its name, title or code.
  def activity_label
    %i[display_title display_name name title code friendly_id email].each do |method|
      next unless respond_to?(method)

      value = public_send(method) rescue nil
      return value.to_s.truncate(120) if value.present?
    end
    "#{self.class.model_name.human} #{id.to_s.first(8)}"
  end

  # The company the entry is filed under: the record's own, or the first
  # parent's that has one.
  def activity_company
    return company if respond_to?(:company) && company.is_a?(Company)

    self.class.reflect_on_all_associations(:belongs_to).each do |association|
      next if association.polymorphic?

      parent = public_send(association.name) rescue nil
      next if parent.nil? || parent == self

      found = parent.respond_to?(:activity_company) ? parent.activity_company : nil
      return found if found
    end
    nil
  end

  private

  def activity_actor
    Thread.current[:current_user]
  end

  def activity_trail_active?
    activity_trail_enabled && activity_actor.present? && !is_a?(AuditLog)
  end

  def governance_trail?
    self.class.include?(GovernanceActivity)
  end

  def write_activity_creation
    return if !activity_trail_active? || governance_trail?

    write_activity("CREATE", {})
  end

  def write_activity_update
    return if !activity_trail_active? || governance_trail?

    changes = saved_changes.except(*QUIET_ATTRIBUTES).reject { |name, _| name.match?(SECRET_ATTRIBUTES) }
    return if changes.empty?

    write_activity("UPDATE", { changes: changes.transform_values { |(before, after)| [ activity_value(before), activity_value(after) ] } })
  end

  def write_activity_deletion
    return unless activity_trail_active?

    write_activity("DELETE", {})
  end

  def write_activity(verb, payload)
    company = activity_company
    return if company.nil?

    entry = AuditLogService.log_action(
      actor_user: activity_actor,
      company: company,
      action: "#{verb}_#{self.class.activity_entity_type.upcase}",
      entity_type: self.class.activity_entity_type,
      entity_id: id,
      payload: payload.merge(label: activity_label),
      automatic: true
    )
    AuditLogService.remember_automatic(entry) if entry
  end

  # Long text is kept short in the entry; the record itself holds the rest.
  def activity_value(value)
    case value
    when String then value.truncate(300)
    when Time, DateTime then value.iso8601
    else value
    end
  end
end
