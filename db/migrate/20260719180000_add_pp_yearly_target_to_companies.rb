class AddPpYearlyTargetToCompanies < ActiveRecord::Migration[8.0]
  # The denominator for the lifecycle funnel. When it is not set, the funnel
  # falls back to the total number of records so the chart is still meaningful.
  def change
    add_column :companies, :pp_yearly_target, :integer
  end
end
