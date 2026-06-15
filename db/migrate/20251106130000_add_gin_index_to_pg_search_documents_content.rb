class AddGinIndexToPgSearchDocumentsContent < ActiveRecord::Migration[8.0]
  def up
    say_with_time("Adding tsvector column and GIN indexes for pg_search") do
      # Add tsvector column for full-text search (tsearch)
      add_column :pg_search_documents, :tsvector_content, :tsvector unless column_exists?(:pg_search_documents, :tsvector_content)

      # Populate tsvector from existing content
      execute <<-SQL
        UPDATE pg_search_documents#{' '}
        SET tsvector_content = to_tsvector('simple', COALESCE(content, ''));
      SQL

      # Create GIN index on tsvector for tsearch performance
      execute <<-SQL
        CREATE INDEX index_pg_search_documents_on_tsvector_content_gin#{' '}
        ON pg_search_documents#{' '}
        USING gin (tsvector_content);
      SQL

      # Create GIN index on content text column for trigram search performance
      execute <<-SQL
        CREATE INDEX index_pg_search_documents_on_content_gin#{' '}
        ON pg_search_documents#{' '}
        USING gin (content gin_trgm_ops);
      SQL

      # Create trigger function to automatically update tsvector when content changes
      execute <<-SQL
        CREATE OR REPLACE FUNCTION update_pg_search_documents_tsvector()
        RETURNS TRIGGER AS $$
        BEGIN
          NEW.tsvector_content := to_tsvector('simple', COALESCE(NEW.content, ''));
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      # Create trigger
      execute <<-SQL
        DROP TRIGGER IF EXISTS pg_search_documents_tsvector_update ON pg_search_documents;
        CREATE TRIGGER pg_search_documents_tsvector_update
        BEFORE INSERT OR UPDATE OF content ON pg_search_documents
        FOR EACH ROW
        EXECUTE FUNCTION update_pg_search_documents_tsvector();
      SQL
    end
  end

  def down
    say_with_time("Removing tsvector column and GIN indexes") do
      # Drop trigger
      execute "DROP TRIGGER IF EXISTS pg_search_documents_tsvector_update ON pg_search_documents;"

      # Drop trigger function
      execute "DROP FUNCTION IF EXISTS update_pg_search_documents_tsvector();"

      # Drop indexes
      remove_index :pg_search_documents, name: "index_pg_search_documents_on_content_gin" if index_exists?(:pg_search_documents, name: "index_pg_search_documents_on_content_gin")
      execute "DROP INDEX IF EXISTS index_pg_search_documents_on_tsvector_content_gin;"

      # Remove tsvector column
      remove_column :pg_search_documents, :tsvector_content if column_exists?(:pg_search_documents, :tsvector_content)
    end
  end
end
