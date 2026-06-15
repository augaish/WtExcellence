namespace :pg_search do
  desc "Reindex all searchable models (Standards, Clauses, ChecklistItems, Capas)"
  task reindex: :environment do
    puts "Starting pg_search reindexing..."

    # Clear existing search documents
    puts "Clearing existing search documents..."
    PgSearch::Document.delete_all
    puts "Cleared existing documents"

    # Reindex Standards
    puts "\nIndexing Standards..."
    count = Standard.count
    PgSearch::Multisearch.rebuild(Standard)
    puts "Indexed #{count} Standards"

    # Reindex Clauses
    puts "\nIndexing Clauses..."
    count = Clause.count
    PgSearch::Multisearch.rebuild(Clause)
    puts "Indexed #{count} Clauses"

    # Reindex ChecklistItems
    puts "\nIndexing ChecklistItems..."
    count = ChecklistItem.count
    PgSearch::Multisearch.rebuild(ChecklistItem)
    puts "Indexed #{count} ChecklistItems"

    # Reindex Capas
    puts "\nIndexing Capas..."
    count = Capa.count
    PgSearch::Multisearch.rebuild(Capa)
    puts "Indexed #{count} Capas"

    total = PgSearch::Document.count
    puts "\nReindexing complete! Total search documents: #{total}"
  end

  desc "Clear all search documents"
  task clear: :environment do
    puts "Clearing all search documents..."
    count = PgSearch::Document.count
    PgSearch::Document.delete_all
    puts "Deleted #{count} search documents"
  end

  desc "Show search index statistics"
  task stats: :environment do
    total = PgSearch::Document.count

    stats = PgSearch::Document.group(:searchable_type).count

    puts "Search Index Statistics:"
    puts "=" * 40
    puts "Total documents: #{total}"
    puts ""
    puts "By type:"
    stats.each do |type, count|
      puts "  #{type}: #{count}"
    end
  end
end
