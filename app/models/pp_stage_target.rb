# Per-company target duration for a stage, in working days.
class PpStageTarget < ApplicationRecord
  belongs_to :company

  validates :stage_key, presence: true, inclusion: { in: PpStage::KEYS }
  validates :stage_key, uniqueness: { scope: :company_id }
  validates :target_days, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Configured value, falling back to the shipped default.
  def self.days_for(company, stage_key)
    company&.stage_target_days&.fetch(stage_key.to_s, nil) ||
      PpStage::DEFAULT_TARGET_DAYS[stage_key.to_s].to_i
  end
end
