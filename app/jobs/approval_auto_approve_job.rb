# Silence counts as approval once the period the P&P Manager set has passed.
# Runs daily; every approval past its deadline is answered "auto_approved" and,
# when that completes the chain, the record moves on.
class ApprovalAutoApproveJob < ApplicationJob
  queue_as :cron_small

  def perform
    stages = PpStage::DEFINITIONS.select { |d| d[:kind] == :approval }.map { |d| d[:key] }
    PpRecord.where(current_stage: stages)
      .where(id: PpStageApproval.pending.where("auto_approve_at <= ?", Time.current).select(:pp_record_id))
      .find_each do |record|
        DocumenterActions.new(record: record, user: nil, company: record.company).auto_approve_overdue!
      end
  end
end
