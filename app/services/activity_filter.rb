# The filters of the Activity page turned into one query: module, record
# type, person, verb, date range, and a word from the record's name.
class ActivityFilter
  attr_reader :module_key, :entity_type, :actor_id, :verb, :from, :to, :query

  def initialize(company, params)
    @company = company
    @module_key = params[:module].presence
    @entity_type = params[:entity_type].presence
    @actor_id = params[:actor_id].presence
    @verb = params[:verb].presence
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @query = params[:q].to_s.strip
  end

  def scope
    scope = AuditLog.where(company_id: @company.id).order(created_at: :desc)
    scope = scope.where(entity_type: ActivityCatalogue.entity_types_for(module_key)) if module_key
    scope = scope.where(entity_type: entity_type) if entity_type
    scope = scope.where(actor_user_id: actor_id) if actor_id
    scope = scope.where("audit_logs.action LIKE ?", "#{verb.upcase}\\_%") if verb
    scope = scope.where("audit_logs.created_at >= ?", from.beginning_of_day) if from
    scope = scope.where("audit_logs.created_at <= ?", to.end_of_day) if to
    scope = scope.where("audit_logs.payload_json->>'label' ILIKE :q OR audit_logs.action ILIKE :q", q: "%#{query}%") if query.present?
    scope
  end

  def any?
    [ module_key, entity_type, actor_id, verb, from, to ].any?(&:present?) || query.present?
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
