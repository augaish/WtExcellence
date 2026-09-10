# A form carries a one-time token; a retry after an uncertain response finds
# the record already created instead of creating it twice.
class SubmissionTokensOnGovernanceRecords < ActiveRecord::Migration[8.0]
  def change
    %i[customer_commitments risks vendors].each do |table|
      add_column table, :submission_token, :string, limit: 64
      add_index table, [ :company_id, :submission_token ], unique: true, where: "submission_token IS NOT NULL"
    end
  end
end
