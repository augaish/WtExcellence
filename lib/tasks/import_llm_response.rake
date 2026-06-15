namespace :ingestion do
  desc "Import LLM response JSON file to latest standard version"
  task :import_llm_response, [ :json_file, :standard_code ] => :environment do |_t, args|
    json_file = args[:json_file] || ENV["JSON_FILE"]
    standard_code = args[:standard_code] || ENV["STANDARD_CODE"]

    unless json_file
      puts "Error: Please provide JSON file path"
      puts "Usage: rake ingestion:import_llm_response[json_file_path,standard_code]"
      puts "   or: JSON_FILE=path STANDARD_CODE=code rake ingestion:import_llm_response"
      exit 1
    end

    unless File.exist?(json_file)
      puts "Error: JSON file not found: #{json_file}"
      exit 1
    end

    puts "Reading JSON file: #{json_file}"
    json_data = JSON.parse(File.read(json_file))

    unless json_data["model"] && json_data["model"]["criteria"]
      puts "Error: Invalid JSON structure. Expected 'model.criteria' array"
      exit 1
    end

    # Find standard
    if standard_code
      standard = Standard.find_by(code: standard_code)
      unless standard
        puts "Error: Standard not found with code: #{standard_code}"
        exit 1
      end
    else
      # Find the most recently created standard
      standard = Standard.order(created_at: :desc).first
      unless standard
        puts "Error: No standards found in database"
        exit 1
      end
      puts "Using most recent standard: #{standard.code}"
    end

    # Get latest version
    standard_version = standard.latest_version
    unless standard_version
      puts "Error: No version found for standard: #{standard.code}"
      exit 1
    end

    puts "Using standard version: #{standard_version.version_label} (ID: #{standard_version.id})"
    puts "Processing #{json_data["model"]["criteria"].length} criteria..."

    ActiveRecord::Base.transaction do
      processor = LlmResponseProcessor.new(standard_version)
      processor.process(json_data)

      clause_count = standard_version.clauses.count
      checkpoint_count = ChecklistItem.joins(:clause).where(clauses: { standard_version_id: standard_version.id }).count

      puts "✅ Successfully imported:"
      puts "   - #{clause_count} clauses"
      puts "   - #{checkpoint_count} checkpoints"
    end
  end
end
