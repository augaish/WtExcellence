class AddTargetAndAppetiteToRisks < ActiveRecord::Migration[8.0]
  def change
    # Inherent, current residual and target are three different things, and the
    # review found the first two conflated and the third missing. Target is an
    # intention; residual is what the evidence supports. Keeping them apart is
    # what stops a low target being read as mitigation already achieved.
    add_column :risks, :target_likelihood, :integer
    add_column :risks, :target_impact, :integer
    add_column :risks, :target_score, :integer

    # The threshold above which exposure needs an explicit decision rather than
    # ordinary management. Null means the company has not set one, in which case
    # nothing is reported as above appetite.
    add_column :companies, :risk_appetite_score, :integer
  end
end
