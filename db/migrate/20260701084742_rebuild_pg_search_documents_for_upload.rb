class RebuildPgSearchDocumentsForUpload < ActiveRecord::Migration[8.0]
  def up
    [ Standard, Clause, ChecklistItem, Capa, Upload ].each do |model|
      model.find_each { |record| PgSearch::Multisearch.rebuild_record(record) }
    end
  end

  def down
    PgSearch::Document.where(searchable_type: "Upload").delete_all
  end
end
