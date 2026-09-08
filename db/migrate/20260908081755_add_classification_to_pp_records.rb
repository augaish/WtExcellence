class AddClassificationToPpRecords < ActiveRecord::Migration[8.0]
  def change
    # Confidentiality classification (تصنيف الوثيقة). Existing records default to
    # "internal", the restrictive-but-workable middle level — never "public",
    # which would widen access to documents nobody has classified yet.
    add_column :pp_records, :classification, :string, limit: 30,
      default: DocumentClassification::DEFAULT_KEY, null: false

    add_index :pp_records, [ :company_id, :classification ]
  end
end
