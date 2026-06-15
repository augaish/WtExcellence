class CreateIngestionJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :ingestion_jobs, id: :uuid do |t|
      t.uuid :standard_id, null: true
      t.uuid :input_pdf_id, null: false
      t.string :status, null: false, default: 'queued'
      t.datetime :started_at
      t.datetime :finished_at
      t.text :message
      t.uuid :created_by

      t.timestamps
    end
    add_foreign_key :ingestion_jobs, :uploads, column: :input_pdf_id
  end
end
