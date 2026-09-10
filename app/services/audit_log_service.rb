class AuditLogService
  # Log an action to the audit log
  #
  # @param actor_user [User] The user performing the action
  # @param company [Company] The company context (can be extracted from entity if not provided)
  # @param action [String] The action name (e.g., 'CREATE_CAPA', 'UPDATE_CAPA')
  # @param entity_type [String] The type of entity (e.g., 'capa', 'capa_action', 'clause')
  # @param entity_id [UUID] The ID of the entity
  # @param payload [Hash] Additional data to store in payload_json
  # @return [AuditLog] The created audit log entry
  # automatic: true when the entry comes from the model's own trail
  # (ActivityTrail). An entry the app writes on purpose for the same record in
  # the same request is the better one, so the automatic entry is folded into
  # it: its changed values are carried over and the plain entry is removed.
  def self.log_action(actor_user:, company: nil, action:, entity_type: nil, entity_id: nil, payload: {}, automatic: false)
    # Skip if no actor user (e.g., system actions)
    return nil unless actor_user

    # Try to extract company from entity if not provided
    resolved_company = company || extract_company_from_entity(entity_type, entity_id)

    # Skip if no company can be determined
    return nil unless resolved_company

    payload = fold_automatic_entries(entity_type, entity_id, payload) unless automatic

    # Wrap the insert in a SAVEPOINT. Audit logging must never break the caller,
    # but in PostgreSQL any failed statement aborts the WHOLE transaction, so
    # rescuing without a savepoint would leave the caller's transaction poisoned
    # and every later statement would fail with InFailedSqlTransaction.
    ActiveRecord::Base.transaction(requires_new: true) do
      AuditLog.create!(
        actor_user_id: actor_user.id,
        company_id: resolved_company.id,
        action: action,
        entity_type: entity_type,
        entity_id: entity_id,
        payload_json: payload
      )
    end
  rescue => e
    # Log error but don't fail the main operation
    Rails.logger.error "Failed to create audit log: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end

  # The automatic entries written so far in this request, by record. Cleared
  # by the request wrapper that sets the acting user.
  def self.pending_automatic_entries
    Thread.current[:activity_trail_entries] ||= Hash.new { |h, k| h[k] = [] }
  end

  def self.remember_automatic(entry)
    pending_automatic_entries[[ entry.entity_type, entry.entity_id ]] << entry
  end

  def self.clear_pending_automatic_entries
    Thread.current[:activity_trail_entries] = nil
  end

  def self.fold_automatic_entries(entity_type, entity_id, payload)
    return payload if entity_type.nil? || entity_id.nil?

    entries = pending_automatic_entries.delete([ entity_type.to_s, entity_id ])
    return payload if entries.blank?

    changes = entries.map { |e| e.payload_json&.dig("changes") }.compact.reduce({}, :merge)
    label = entries.map { |e| e.payload_json&.dig("label") }.compact.last
    entries.each(&:destroy)
    folded = payload.dup
    folded[:changes] = changes if changes.any? && !folded.key?(:changes) && !folded.key?("changes")
    folded[:label] = label if label && !folded.key?(:label) && !folded.key?("label")
    folded
  end

  private

  def self.extract_company_from_entity(entity_type, entity_id)
    return nil unless entity_type && entity_id

    case entity_type.to_s
    when "capa"
      capa = Capa.find_by(id: entity_id)
      capa&.company
    when "capa_action"
      action = CapaAction.find_by(id: entity_id)
      action&.capa&.company
    when "clause"
      clause = Clause.find_by(id: entity_id)
      clause&.standard_version&.standard&.company_standards&.first&.company
    when "assessment"
      assessment = Assessment.find_by(id: entity_id)
      assessment&.company
    when "tool"
      # Tools don't have a direct company, but we can get it from associated users
      # or from the current context - this will be handled by passing company explicitly
      nil
    when "company"
      company = Company.find_by(id: entity_id)
      company
    when "user"
      user = User.find_by(id: entity_id)
      user&.company_user&.company
    else
      nil
    end
  end
end
