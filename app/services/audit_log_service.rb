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
  def self.log_action(actor_user:, company: nil, action:, entity_type: nil, entity_id: nil, payload: {})
    # Skip if no actor user (e.g., system actions)
    return nil unless actor_user

    # Try to extract company from entity if not provided
    resolved_company = company || extract_company_from_entity(entity_type, entity_id)

    # Skip if no company can be determined
    return nil unless resolved_company

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
