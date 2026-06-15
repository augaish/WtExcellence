class CreditService
  class InsufficientCreditsError < StandardError; end
  class InvalidAssignmentError < StandardError; end

  # Credit costs for different AI operations (fallback if database is not available)
  CREDIT_COSTS = {
    "GENERATE_CAPA_ACTIONS" => 5,
    "GENERATE_CAPA_QUESTIONNAIRE" => 0,
    "SUGGEST_CAPA_CLAUSES" => 7,
    "REGENERATE_ROOT_CAUSE" => 0
  }.freeze

  CACHE_KEY = "credit_costs_cache"
  CACHE_EXPIRY = 1.hour

  def self.get_cost(action_type)
    cost = get_cost_from_db(action_type)
    return cost if cost

    # Fallback to constant if database value not found
    CREDIT_COSTS[action_type] || 0
  end

  def self.has_sufficient_credits?(_company, action_type, company_user: nil)
    return false unless company_user

    required_credits = get_cost(action_type)
    return true if required_credits == 0 # Free operations always have sufficient credits

    company_user.assigned_credits.to_i >= required_credits
  end

  def self.deduct_credits(_company, action_type, company_user: nil)
    return false unless company_user

    required_credits = get_cost(action_type)
    return true if required_credits == 0 # Free operations don't deduct credits
    return false unless has_sufficient_credits?(company_user.company, action_type, company_user: company_user)

    Company.transaction do
      company_user.lock!

      assigned_available = company_user.assigned_credits.to_i
      raise InsufficientCreditsError, "Insufficient user credits" if assigned_available < required_credits

      company_user.update!(assigned_credits: assigned_available - required_credits)
    end

    true
  rescue InsufficientCreditsError => e
    Rails.logger.warn "Credit deduction failed: #{e.message}"
    false
  rescue => e
    Rails.logger.error "Failed to deduct credits: #{e.message}"
    false
  end

  def self.set_user_credit_balance!(company_user, new_balance)
    raise InvalidAssignmentError, "User is required" unless company_user

    company = company_user.company
    raise InvalidAssignmentError, "Company is required" unless company

    new_balance = new_balance.to_i
    raise InvalidAssignmentError, "Assigned credits must be greater than or equal to 0" if new_balance.negative?

    Company.transaction do
      company.lock!
      company_user.lock!

      delta = new_balance - company_user.assigned_credits
      if delta.positive?
        raise InsufficientCreditsError, "Not enough company credits" if company.credits < delta
        company.update!(credits: company.credits - delta)
      elsif delta.negative?
        company.update!(credits: company.credits - delta)
      end

      company_user.update!(assigned_credits: new_balance)
    end

    company_user
  rescue ActiveRecord::RecordInvalid => e
    raise InvalidAssignmentError, e.message
  end

  def self.set_company_credits!(company, new_balance)
    raise InvalidAssignmentError, "Company is required" unless company

    new_balance = Integer(new_balance)
    raise InvalidAssignmentError, "Company credits must be greater than or equal to 0" if new_balance.negative?

    Company.transaction do
      company.lock!
      company.update!(credits: new_balance)
    end

    company
  rescue ArgumentError, TypeError
    raise InvalidAssignmentError, "Company credits must be greater than or equal to 0"
  rescue ActiveRecord::RecordInvalid => e
    raise InvalidAssignmentError, e.message
  end

  # Clear the cache (call this after updating credit costs)
  def self.clear_cache
    Rails.cache.delete(CACHE_KEY)
  end

  private

  def self.get_cost_from_db(action_type)
    return nil unless action_type.present?

    # Try to get from cache first
    cached_costs = Rails.cache.read(CACHE_KEY)
    if cached_costs
      return cached_costs[action_type]
    end

    # If not in cache, load from database and cache it
    begin
      costs = AiActionCredit.all_costs
      Rails.cache.write(CACHE_KEY, costs, expires_in: CACHE_EXPIRY)
      costs[action_type]
    rescue => e
      Rails.logger.error "Failed to load credit costs from database: #{e.message}"
      nil
    end
  end
end

