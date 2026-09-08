class AddChangeSummaryToPpRecords < ActiveRecord::Migration[8.0]
  def change
    # What changed in this version. The change log was printing the record's
    # description, truncated, which describes the document rather than the
    # change to it.
    add_column :pp_records, :change_summary, :text
  end
end
