namespace :tools do
  desc "Sync existing tools to translation tables (English source) and auto-translate to Arabic via OpenRouter"
  task sync_translations: :environment do
    source_locale = "en"
    target_locales = %w[ar]

    OpenRouter.configure do |config|
      config.access_token = ENV.fetch("OPENROUTER_API_KEY")
      config.site_name = "Way to Excellence"
      config.site_url = ENV.fetch("APP_URL", "http://localhost:3000")
    end
    or_client = OpenRouter::Client.new
    or_model = ENV.fetch("OPENROUTER_MODEL", "anthropic/claude-sonnet-4-20250514")

    tools = Tool.includes(checkpoints: :subcheckpoints).all
    puts "Found #{tools.count} tools to sync"

    tools.each_with_index do |tool, i|
      puts "\n[#{i + 1}/#{tools.count}] #{tool.name}"

      # --- English (source) ---
      upsert_tool_translation(tool, source_locale)

      tool.checkpoints.each do |checkpoint|
        upsert_checkpoint_translation(checkpoint, source_locale)
        checkpoint.subcheckpoints.each do |sub|
          upsert_subcheckpoint_translation(sub, source_locale)
        end
      end

      # --- Arabic (auto-translate via OpenRouter) ---
      target_locales.each do |target_locale|
        translate_tool(tool, or_client, or_model, source_locale, target_locale)
        tool.checkpoints.each do |checkpoint|
          translate_checkpoint(checkpoint, or_client, or_model, source_locale, target_locale)
          checkpoint.subcheckpoints.each do |sub|
            translate_subcheckpoint(sub, or_client, or_model, source_locale, target_locale)
          end
        end
      end

      puts "  Done."
    end

    puts "\nAll tools synced!"
  end
end

def upsert_tool_translation(tool, locale)
  t = tool.tool_translations.find_or_initialize_by(language_code: locale)
  t.name = tool.name
  t.description = tool.description
  t.needs_review = false
  t.ai_generated = false
  t.save!
end

def upsert_checkpoint_translation(checkpoint, locale)
  t = checkpoint.tool_checkpoint_translations.find_or_initialize_by(language_code: locale)
  t.name = checkpoint.name
  t.needs_review = false
  t.ai_generated = false
  t.save!
end

def upsert_subcheckpoint_translation(sub, locale)
  t = sub.tool_subcheckpoint_translations.find_or_initialize_by(language_code: locale)
  t.name = sub.name
  t.description = sub.description
  t.multiple_choice_options = normalize_options(sub.multiple_choice_options)
  t.needs_review = false
  t.ai_generated = false
  t.save!
end

def translate_tool(tool, client, model, source_locale, target_locale)
  t = tool.tool_translations.find_or_initialize_by(language_code: target_locale)

  translated_name = translate_text_openrouter(client, model, tool.name, source_locale, target_locale)
  translated_desc = translate_text_openrouter(client, model, tool.description, source_locale, target_locale)

  persist_translation(t, {
    name: translated_name.presence || "[Translation needed]",
    description: translated_desc.presence || tool.description,
    needs_review: true,
    ai_generated: true,
    source_updated_at: Time.current,
    last_modified_at: Time.current
  })
  print "  T"
end

def translate_checkpoint(checkpoint, client, model, source_locale, target_locale)
  t = checkpoint.tool_checkpoint_translations.find_or_initialize_by(language_code: target_locale)

  translated_name = translate_text_openrouter(client, model, checkpoint.name, source_locale, target_locale)

  persist_translation(t, {
    name: translated_name.presence || "[Translation needed]",
    needs_review: true,
    ai_generated: true,
    source_updated_at: Time.current,
    last_modified_at: Time.current
  })
  print "."
end

def translate_subcheckpoint(sub, client, model, source_locale, target_locale)
  t = sub.tool_subcheckpoint_translations.find_or_initialize_by(language_code: target_locale)

  translated_name = translate_text_openrouter(client, model, sub.name, source_locale, target_locale)
  translated_desc = translate_text_openrouter(client, model, sub.description, source_locale, target_locale)
  translated_options = normalize_options(sub.multiple_choice_options).map do |option|
    translated_text = translate_text_openrouter(client, model, option["text"], source_locale, target_locale)
    option.merge("text" => translated_text.presence || "[Translation needed]")
  end

  persist_translation(t, {
    name: translated_name.presence || "[Translation needed]",
    description: translated_desc.presence || sub.description,
    multiple_choice_options: translated_options,
    needs_review: true,
    ai_generated: true,
    source_updated_at: Time.current,
    last_modified_at: Time.current
  })
  print "."
end

def translate_text_openrouter(client, model, text, source_language, target_language)
  return nil if text.blank?

  language_names = { "en" => "English", "ar" => "Arabic" }
  source_name = language_names[source_language] || source_language
  target_name = language_names[target_language] || target_language

  messages = [
    {
      role: "system",
      content: "You are a strict translation engine. Return ONLY the translation, nothing else.\n\nRULES:\n- No explanations, notes, alternatives, comments, or quotes.\n- Keep acronyms and abbreviations exactly as-is (e.g. EFQM, D&E, ISO, QMS, CAPA).\n- If the input is only an acronym or very short technical term that doesn't need translation, return it exactly as-is.\n- Preserve technical meaning and terms.\n- Keep output in #{target_name} only."
    },
    {
      role: "user",
      content: "Translate from #{source_name} to #{target_name}:\n\n#{text}"
    }
  ]

  response = client.complete(messages, model: model)

  content = response.dig("choices", 0, "message", "content").to_s.strip
  content = content.gsub(/^["']|["']$/, "")
  content.presence
rescue => e
  puts "\n  WARNING: Translation failed: #{e.message}"
  nil
end

def persist_translation(record, attrs)
  if record.new_record?
    record.assign_attributes(attrs)
    record.save!
  else
    record.update_columns(attrs)
  end
end

def normalize_options(options)
  return [] unless options.is_a?(Array)

  options.filter_map do |option|
    next unless option.is_a?(Hash)
    {
      "text" => (option["text"] || option[:text]).to_s,
      "weight" => (option["weight"] || option[:weight]).to_i
    }
  end
end
