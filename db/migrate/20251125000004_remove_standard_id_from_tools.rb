class RemoveStandardIdFromTools < ActiveRecord::Migration[8.0]
  def up
    # Tools should not be tied to a single standard; they can be reused across standards.
    if foreign_key_exists?(:tools, :standards)
      remove_foreign_key :tools, :standards
    end

    if column_exists?(:tools, :standard_id)
      remove_column :tools, :standard_id
    end
  end

  def down
    # Restore the legacy standard_id column if needed (kept nullable, since tools can exist without a standard)
    unless column_exists?(:tools, :standard_id)
      add_reference :tools, :standard, type: :uuid, foreign_key: true
    end
  end
end


