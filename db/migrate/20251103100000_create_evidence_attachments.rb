class CreateEvidenceAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :evidence_attachments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :upload, null: false, foreign_key: true, type: :uuid
      t.uuid :attachable_id, null: false
      t.string :attachable_type, null: false, limit: 50
      t.string :purpose, limit: 50
      t.text :notes
      t.uuid :attached_by
      t.timestamps
    end

    # Indexes for efficient queries
    # Unique constraint: one upload can only be linked once to each entity
    # Note: upload_id index is automatically created by t.references above
    add_index :evidence_attachments, [ :upload_id, :attachable_type, :attachable_id ],
              unique: true, name: 'index_evidence_attachments_on_upload_and_attachable'
    add_index :evidence_attachments, [ :attachable_type, :attachable_id ],
              name: 'index_evidence_attachments_on_attachable'
    add_index :evidence_attachments, :attached_by
  end
end
