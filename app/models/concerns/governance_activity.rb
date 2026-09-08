# A consistent activity trail for the governance records — Risk, Vendor and
# Customer Commitment.
#
# The review asked each module to be able to answer "what changed, by whom, and
# when". Risk answered it with a hand-written method listing its own fields;
# Vendor and Customer Commitment did not answer it at all, so an edit to either
# left no trace. One concern gives all three the same trail and keeps the audit
# actions and entity names Risk already writes, so existing history stays
# readable.
#
# Only material attributes are tracked. Logging every column would bury the
# score change that matters under the timestamp that does not.
module GovernanceActivity
  extend ActiveSupport::Concern

  included do
    class_attribute :tracked_attributes, instance_writer: false, default: [].freeze
    class_attribute :activity_entity_type, instance_writer: false
    class_attribute :activity_summary_attributes, instance_writer: false, default: [].freeze

    after_create :log_governance_creation
    after_update :log_governance_update
  end

  class_methods do
    # entity: the audit entity_type, which also forms the action names
    #         ("risk" -> CREATE_RISK / UPDATE_RISK).
    # tracks: the attributes whose old and new values are worth keeping.
    # summary: the attributes recorded when the record is first created.
    def tracks_governance_activity(entity:, tracks:, summary: [])
      self.activity_entity_type = entity.to_s
      self.tracked_attributes = tracks.map(&:to_s).freeze
      self.activity_summary_attributes = summary.map(&:to_s).freeze
    end
  end

  # The record's own history, newest first, read back from the audit log.
  def activity_trail(limit: 50)
    return AuditLog.none if activity_entity_type.blank?

    AuditLog.where(entity_type: activity_entity_type, entity_id: id)
            .order(created_at: :desc)
            .limit(limit)
  end

  private

  # Changes are only attributable when someone is acting. A background job
  # touching a record writes no entry rather than an anonymous one, which would
  # be worse than silence in an audit trail.
  def governance_actor
    Thread.current[:current_user]
  end

  def log_governance_creation
    actor = governance_actor
    return if actor.nil? || activity_entity_type.blank?

    write_governance_log(actor, "CREATE_#{activity_entity_type.upcase}",
      activity_summary_attributes.index_with { |name| public_send(name) })
  end

  def log_governance_update
    actor = governance_actor
    return if actor.nil? || activity_entity_type.blank?

    changes = tracked_attributes.each_with_object({}) do |name, collected|
      change = saved_change_to_attribute(name)
      collected[name] = change if change
    end
    return if changes.empty?

    write_governance_log(actor, "UPDATE_#{activity_entity_type.upcase}", { changes: changes })
  end

  def write_governance_log(actor, action, payload)
    AuditLogService.log_action(
      actor_user: actor,
      company: company,
      action: action,
      entity_type: activity_entity_type,
      entity_id: id,
      payload: payload
    )
  end
end
