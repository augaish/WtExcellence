class ToolSubcheckpoint < ApplicationRecord
  # Validations
  validates :name, presence: true
  validates :scoring_type, inclusion: { in: [ "Number", "Percentage", "Multiple Choice" ], allow_blank: true }
  validates :min_score, numericality: { allow_nil: true, allow_blank: true }
  validates :max_score, numericality: { allow_nil: true, allow_blank: true }
  validates :weight, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :is_cap, inclusion: { in: [ true, false ] }
  validate :max_score_greater_than_min_score
  validate :multiple_choice_options_format

  # Associations
  belongs_to :tool_checkpoint, foreign_key: "tool_checkpoints_id", inverse_of: :subcheckpoints
  has_many :assessment_scores, dependent: :destroy
  has_many :tool_subcheckpoint_translations, dependent: :destroy

  # Store multiple_choice_options as JSONB array
  # Rails will automatically handle JSONB serialization

  def name_in(locale = I18n.locale.to_s)
    tool_subcheckpoint_translations.find_by(language_code: locale)&.name.presence || name
  end

  def description_in(locale = I18n.locale.to_s)
    tool_subcheckpoint_translations.find_by(language_code: locale)&.description.presence || description
  end

  def multiple_choice_options_in(locale = I18n.locale.to_s)
    translation = tool_subcheckpoint_translations.find_by(language_code: locale)
    options = translation&.multiple_choice_options
    return options if options.present?

    multiple_choice_options
  end

  def translation_for(locale = I18n.locale.to_s)
    tool_subcheckpoint_translations.find_by(language_code: locale)
  end

  private

  def max_score_greater_than_min_score
    return if min_score.blank? || max_score.blank?

    if max_score <= min_score
      errors.add(:max_score, "must be greater than min score")
    end
  end

  def multiple_choice_options_format
    return unless scoring_type == "Multiple Choice"
    return if multiple_choice_options.blank?

    unless multiple_choice_options.is_a?(Array)
      errors.add(:multiple_choice_options, "must be an array")
      return
    end

    multiple_choice_options.each_with_index do |option, index|
      unless option.is_a?(Hash) && option["text"].present?
        errors.add(:multiple_choice_options, "option at index #{index} must have a text field")
      end
    end
  end
end
