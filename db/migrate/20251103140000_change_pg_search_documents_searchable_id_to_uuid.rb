class ChangePgSearchDocumentsSearchableIdToUuid < ActiveRecord::Migration[8.0]
  def up
    # Clear existing documents since they would have invalid IDs anyway
    execute "TRUNCATE TABLE pg_search_documents" if table_exists?(:pg_search_documents)

    # Remove the index first
    remove_index :pg_search_documents, name: "index_pg_search_documents_on_searchable" if index_exists?(:pg_search_documents, [ :searchable_type, :searchable_id ], name: "index_pg_search_documents_on_searchable")

    # Drop and recreate the column with the correct type
    remove_column :pg_search_documents, :searchable_id
    add_column :pg_search_documents, :searchable_id, :uuid

    # Recreate the index with the new type
    add_index :pg_search_documents, [ :searchable_type, :searchable_id ], name: "index_pg_search_documents_on_searchable"
  end

  def down
    # Clear existing documents
    execute "TRUNCATE TABLE pg_search_documents"

    # Remove index
    remove_index :pg_search_documents, name: "index_pg_search_documents_on_searchable" if index_exists?(:pg_search_documents, [ :searchable_type, :searchable_id ], name: "index_pg_search_documents_on_searchable")

    # Drop and recreate the column back to bigint
    remove_column :pg_search_documents, :searchable_id
    add_column :pg_search_documents, :searchable_id, :bigint

    # Recreate index
    add_index :pg_search_documents, [ :searchable_type, :searchable_id ], name: "index_pg_search_documents_on_searchable"
  end
end
