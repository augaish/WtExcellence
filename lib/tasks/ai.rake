namespace :ai do
  # Prints the effective AI configuration and makes a live test call so the
  # actual provider error (402, invalid model, unreachable Ollama, …) is
  # visible instead of the generic "sorry" the UI shows.
  #
  #   bin/rails ai:doctor
  #   bin/kamal app exec -d wtexcel --reuse "bin/rails ai:doctor"
  desc "Diagnose the AI/LLM configuration and make a live test call"
  task doctor: :environment do
    mask = ->(v) { v.present? ? "#{v[0, 6]}…(#{v.length} chars)" : "(not set)" }

    puts "== AI / LLM configuration =="
    puts "OPENROUTER_API_KEY:            #{mask.call(ENV['OPENROUTER_API_KEY'])}"
    puts "OPENROUTER_MODEL:             #{ENV['OPENROUTER_MODEL'].presence || '(unset → default anthropic/claude-sonnet-4.5)'}"
    puts "OLLAMA_URL:                   #{ENV['OLLAMA_URL'].presence || '(unset → http://localhost:11434)'}"
    %w[CAPA_ACTION_PROVIDER CAPA_CLAUSE_PROVIDER CAPA_QUESTIONNAIRE_PROVIDER].each do |k|
      puts "#{k.ljust(30)}#{ENV[k].presence || '(unset → default openrouter)'}"
    end
    puts

    model = ENV["OPENROUTER_MODEL"].presence || "anthropic/claude-sonnet-4.5"
    puts "== Live OpenRouter test call (model: #{model}) =="

    if ENV["OPENROUTER_API_KEY"].blank?
      puts "SKIP: OPENROUTER_API_KEY is not set — the app cannot call OpenRouter."
      next
    end

    begin
      OpenRouter.configure do |config|
        config.access_token = ENV.fetch("OPENROUTER_API_KEY")
        config.site_name = "Way to Excellence"
        config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
      end
      client = OpenRouter::Client.new
      response = client.complete(
        [ { role: "user", content: "Reply with the single word: OK" } ],
        model: model
      )
      content = response.dig("choices", 0, "message", "content")
      puts "SUCCESS: model replied → #{content.inspect}"
      puts "The AI path is working. If the UI still fails, check the per-feature CAPA_*_PROVIDER vars above."
    rescue => e
      puts "FAILURE: #{e.class}: #{e.message}"
      puts
      puts "Common causes:"
      puts "  • 402 Payment Required → the OpenRouter account has no credit balance."
      puts "  • 400/404 invalid model → OPENROUTER_MODEL slug is wrong or deprecated."
      puts "  • 401 → OPENROUTER_API_KEY is missing or invalid."
      puts "  • free model errors → some ':free' models are rate-limited or retired; try another."
    end
  end
end
