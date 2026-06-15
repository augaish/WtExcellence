class DropCapaUploads < ActiveRecord::Migration[8.0]
  def change
    # Only drop the table if it exists (safe for merged branches)
    if table_exists?(:capa_uploads)
      drop_table :capa_uploads do |t|
        t.uuid :capa_id, null: false
        t.uuid :upload_id, null: false
        t.text :notes
        t.timestamps
      end
    end
  end
end
