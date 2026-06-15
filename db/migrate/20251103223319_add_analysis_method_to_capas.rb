class AddAnalysisMethodToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :analysis_method, :string, default: 'manual'
  end
end
