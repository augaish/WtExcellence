class AddProgressStageToIngestionJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :ingestion_jobs, :progress_stage, :string
  end
end
