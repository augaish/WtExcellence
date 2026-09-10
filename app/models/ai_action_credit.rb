class AiActionCredit < ApplicationRecord
  skip_activity_trail
  DISPLAY_NAMES = {
    "GENERATE_CAPA_ACTIONS" => "Generate Actions",
    "GENERATE_CAPA_QUESTIONNAIRE" => "Generate Questionnaire",
    "SUGGEST_CAPA_CLAUSES" => "Suggest Clauses",
    "REGENERATE_ROOT_CAUSE" => "Regenerate Root Cause"
  }.freeze

  validates :action_type, presence: true, uniqueness: true
  validates :credit_cost, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :display_name, presence: true

  # Get credit cost for an action type
  def self.get_cost_for(action_type)
    find_by(action_type: action_type)&.credit_cost
  end

  # Get all costs as a hash (for caching)
  def self.all_costs
    all.index_by(&:action_type).transform_values(&:credit_cost)
  end

  def self.ensure_defaults!
    CreditService::CREDIT_COSTS.each do |action_type, default_cost|
      find_or_create_by!(action_type: action_type) do |credit|
        credit.credit_cost = default_cost
        credit.display_name = DISPLAY_NAMES[action_type] || action_type.titleize
      end
    end
  end
end

