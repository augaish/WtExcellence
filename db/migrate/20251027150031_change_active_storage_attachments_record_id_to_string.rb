class ChangeActiveStorageAttachmentsRecordIdToString < ActiveRecord::Migration[8.0]
  def up
    change_column :active_storage_attachments, :record_id, :string
  end

  def down
    change_column :active_storage_attachments, :record_id, :bigint
  end
end
