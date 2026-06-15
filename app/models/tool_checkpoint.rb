class ToolCheckpoint < ApplicationRecord
  # Validations
  validates :name, presence: true

  # Associations
  belongs_to :tool, inverse_of: :checkpoints
  has_many :subcheckpoints, class_name: "ToolSubcheckpoint", foreign_key: "tool_checkpoints_id", dependent: :destroy, inverse_of: :tool_checkpoint
  has_many :tool_checkpoint_translations, dependent: :destroy
  has_many :checkpoint_summaries, dependent: :destroy
  accepts_nested_attributes_for :subcheckpoints, allow_destroy: true

  def name_in(locale = I18n.locale.to_s)
    tool_checkpoint_translations.find_by(language_code: locale)&.name.presence || name
  end

  def translation_for(locale = I18n.locale.to_s)
    tool_checkpoint_translations.find_by(language_code: locale)
  end
end
