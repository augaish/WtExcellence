# The language a document is written in, chosen on the record rather than
# guessed from its title.
class AddLanguageToPpRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :pp_records, :language, :string, limit: 2
  end
end
