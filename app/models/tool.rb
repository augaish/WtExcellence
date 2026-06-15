class Tool < ApplicationRecord
  # Validations
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  # Associations
  has_many :checkpoints, class_name: "ToolCheckpoint", dependent: :destroy, inverse_of: :tool
  has_many :tool_clauses, dependent: :destroy
  has_many :clauses, through: :tool_clauses
  has_many :tool_translations, dependent: :destroy

  accepts_nested_attributes_for :checkpoints, allow_destroy: true

  def name_in(locale = I18n.locale.to_s)
    tool_translations.find_by(language_code: locale)&.name.presence || name
  end

  def description_in(locale = I18n.locale.to_s)
    tool_translations.find_by(language_code: locale)&.description.presence || description
  end

  def translation_for(locale = I18n.locale.to_s)
    tool_translations.find_by(language_code: locale)
  end

  # All subcheckpoints across all checkpoints for this tool, ordered
  def all_subcheckpoints
    checkpoints.includes(:subcheckpoints)
               .order(:display_order)
               .flat_map { |cp| cp.subcheckpoints.order(:display_order) }
  end

  # Effective weights: configured or equal fallback when all null.
  # Stored as 0-100 percent in the DB; returned here as 0-1 fractions so the
  # scoring calculator can stay format-agnostic.
  def effective_weights
    subs = all_subcheckpoints
    return {} if subs.empty?

    all_null = subs.all? { |s| s.weight.nil? }
    equal_weight = 1.0 / subs.size

    subs.each_with_object({}) do |sub, h|
      h[sub.id] = all_null ? equal_weight : ((sub.weight&.to_f || 0.0) / 100.0)
    end
  end

  # Subcheckpoint IDs marked as caps
  def cap_subcheckpoint_ids
    all_subcheckpoints.select(&:is_cap).map(&:id)
  end

  # Score calculation methods
  def calculate_total_score
    total_score = 0
    total_allocated = 0
    
    tool_clauses.includes(clause: :children).each do |tool_clause|
      calculator = ClauseScoreCalculator.new(tool_clause)
      result = calculator.calculate_score(nil) # Company not available in this context - will show all assignments
      
      total_score += result[:score]
      total_allocated += result[:allocated_points]
    end
    
    {
      total_score: total_score.round(2),
      total_allocated: total_allocated,
      percentage: total_allocated > 0 ? ((total_score / total_allocated) * 100).round(2) : 0
    }
  end

  def score_by_top_level_clause
    scores = {}
    
    # Group clauses by their top-level parent
    clauses.includes(:parent).each do |clause|
      top_level = clause
      while top_level.parent.present?
        top_level = top_level.parent
      end
      
      scores[top_level] ||= { clauses: [], total_score: 0, total_allocated: 0 }
      
      tool_clause = tool_clauses.find_by(clause_id: clause.id)
      next unless tool_clause
      
      calculator = ClauseScoreCalculator.new(tool_clause)
      result = calculator.calculate_score(nil) # Company not available in this context - will show all assignments
      
      scores[top_level][:clauses] << { clause: clause, **result }
      scores[top_level][:total_score] += result[:score]
      scores[top_level][:total_allocated] += result[:allocated_points]
    end
    
    # Calculate percentages
    scores.each do |top_level, data|
      data[:percentage] = data[:total_allocated] > 0 ? 
        ((data[:total_score] / data[:total_allocated]) * 100).round(2) : 0
    end
    
    scores
  end

end
