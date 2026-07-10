class AddHeartbeatToIngestionJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :ingestion_jobs, :heartbeat_at, :datetime
    add_column :ingestion_jobs, :progress_detail, :string
  end
end
