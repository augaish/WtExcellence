class AddBusinessRuleViolationToClauseScoreCaches < ActiveRecord::Migration[8.0]
  def change
    add_column :clause_score_caches, :business_rule_violation, :text
  end
end

