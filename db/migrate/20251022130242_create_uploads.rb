class CreateUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :uploads, id: :uuid do |t|
      t.string :storage_path, null: false, limit: 500
      t.string :filename, null: false, limit: 255
      t.string :mime_type
      t.bigint :size_bytes
      t.uuid :uploaded_by

      t.timestamps
    end
  end
end
