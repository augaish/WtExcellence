#!/usr/bin/env ruby
# frozen_string_literal: true

# Syncs Arabic locale YAML files with client-modified translations from two XLSX files.
#
# File 1 (keys file): columns = [key, english, arabic]
# File 2 (clients file): columns = [english, arabic]  (same row order as file 1)
#
# Where to put the XLSX files (any path works; this is a suggestion):
#   tmp/locale_sync/keys_file.xlsx   — key, English, Arabic (your reference)
#   tmp/locale_sync/client_arabic.xlsx — English, Arabic (client’s modified version)
#
# Usage:
#   bundle exec ruby script/sync_arabic_locales_from_xlsx.rb FILE1.xlsx FILE2.xlsx [--dry-run]
#
# Example (if you use the suggested folder and names):
#   bundle exec ruby script/sync_arabic_locales_from_xlsx.rb tmp/locale_sync/keys_file.xlsx tmp/locale_sync/client_arabic.xlsx --dry-run
#
# Options:
#   --dry-run       Only print what would be changed; do not write YAML files.
#   --no-header     First row is data (default: first row is header and skipped).
#   --add-missing   Add keys to Arabic locale files if they exist in English but not in Arabic
#                   (so client translations can be applied; creates devise.ar.yml if needed).

require "roo"
require "yaml"
require "fileutils"

def usage
  puts <<~USAGE
    Usage: #{$PROGRAM_NAME} <keys_file.xlsx> <clients_file.xlsx> [options]

    File 1 (keys):  column A = key, B = English, C = Arabic
    File 2 (client): column A = English, B = Arabic (same row order)

    Options:
      --dry-run       Show changes only; do not write locale files
      --no-header     Treat first row as data (default: skip first row as header)
      --add-missing   Add missing keys to Arabic files from English locale so they can be updated
  USAGE
  exit 1
end

def parse_args
  args = ARGV.dup
  dry_run = args.delete("--dry-run")
  no_header = args.delete("--no-header")
  add_missing = args.delete("--add-missing")
  usage if args.size < 2
  [args[0], args[1], dry_run, no_header, add_missing]
end

def read_xlsx_rows(path, columns:, skip_header: true)
  xlsx = Roo::Spreadsheet.open(path)
  sheet = xlsx.sheet(0)
  last = sheet.last_row.to_i
  return [] if last < 1

  start_row = skip_header ? 2 : 1
  rows = []
  start_row.upto(last) do |i|
    raw = sheet.row(i)
    row = columns.map { |col| (raw[col] || "").to_s.strip }
    rows << row
  end
  rows
end

def flatten_keys_recursive(hash, prefix = nil)
  result = {}
  hash.each do |k, v|
    key = prefix ? "#{prefix}.#{k}" : k.to_s
    if v.is_a?(Hash)
      result.merge!(flatten_keys_recursive(v, key))
    else
      result[key] = v
    end
  end
  result
end

def find_ar_locale_files(locales_dir)
  dir = File.expand_path(locales_dir)
  files = []
  files << File.join(dir, "ar.yml") if File.file?(File.join(dir, "ar.yml"))
  files << File.join(dir, "ar_datetime.yml") if File.file?(File.join(dir, "ar_datetime.yml"))
  Dir[File.join(dir, "**", "*.ar.yml")].each { |f| files << f }
  files.uniq
end

def find_en_locale_files(locales_dir)
  dir = File.expand_path(locales_dir)
  files = []
  files << File.join(dir, "en.yml") if File.file?(File.join(dir, "en.yml"))
  Dir[File.join(dir, "**", "*.en.yml")].each { |f| files << f }
  files.uniq
end

def en_file_to_ar_file(en_path)
  dir = File.dirname(en_path)
  base = File.basename(en_path)
  if base == "en.yml"
    File.join(dir, "ar.yml")
  else
    # devise.en.yml -> devise.ar.yml, capa_show.en.yml -> capa_show.ar.yml
    ar_base = base.sub(/\.en\.yml\z/, ".ar.yml")
    ar_base = "ar.yml" if ar_base == base
    File.join(dir, ar_base)
  end
end

def load_en_locale_file(file_path)
  data = YAML.load_file(file_path)
  return {} unless data.is_a?(Hash)

  # Top-level key can be "en" or locale name
  content = data["en"] || data[data.keys.first]
  content.is_a?(Hash) ? content : {}
end

def build_key_to_en_file(locales_dir)
  key_to_en_file = {}
  en_files = find_en_locale_files(locales_dir)
  en_files.each do |path|
    content = load_en_locale_file(path)
    next if content.empty?

    flatten_keys_recursive(content).each_key do |key|
      key_to_en_file[key] = path
    end
  end
  key_to_en_file
end

def deep_set_creating(hash, dotted_key, value)
  parts = dotted_key.split(".")
  current = hash
  parts.each_with_index do |part, i|
    if i == parts.size - 1
      current[part] = value
    else
      current[part] = {} unless current[part].is_a?(Hash)
      current = current[part]
    end
  end
end

def load_ar_locale_file(file_path)
  return [nil, {}] unless File.file?(file_path)

  data = YAML.load_file(file_path)
  return [nil, {}] unless data.is_a?(Hash) && data["ar"]

  [data, data["ar"]]
end

def build_key_to_file_and_content(locale_files)
  key_to_file = {}
  file_to_full_data = {}   # path => full YAML hash (e.g. {"ar" => {...}})
  file_to_ar_hash = {}     # path => content under "ar" (for in-place updates)
  locale_files.each do |path|
    full_data, ar_content = load_ar_locale_file(path)
    next if ar_content.empty?

    file_to_full_data[path] = full_data
    file_to_ar_hash[path] = ar_content
    flatten_keys_recursive(ar_content).each_key do |key|
      key_to_file[key] = path
    end
  end
  [key_to_file, file_to_full_data, file_to_ar_hash]
end

def normalize_for_match(str)
  str.to_s.strip.gsub(/\s+/, " ")
end

def build_updates(file1_path, file2_path, skip_header:)
  rows1 = read_xlsx_rows(file1_path, columns: [0, 1, 2], skip_header: skip_header)
  rows2 = read_xlsx_rows(file2_path, columns: [0, 1], skip_header: skip_header)

  # Build key => new_arabic by row index (same row = same key)
  updates = {}
  n = [rows1.size, rows2.size].min
  n.times do |i|
    key = rows1[i][0]
    next if key.to_s.empty?

    client_arabic = rows2[i][1]
    updates[key] = client_arabic
  end

  # If row counts differ, try matching by English text for remaining rows
  if rows1.size != rows2.size
    en_to_arabic = {}
    rows2.each { |en, ar| en_to_arabic[normalize_for_match(en)] = ar }
    rows1.each do |key, en, _ar|
      next if key.to_s.empty?
      next if updates.key?(key)

      norm_en = normalize_for_match(en)
      updates[key] = en_to_arabic[norm_en] if en_to_arabic[norm_en]
    end
  end

  updates
end

def apply_updates_and_save(file_to_full_data, file_to_ar_hash, key_to_file, updates, dry_run:)
  file_updates = Hash.new { |h, k| h[k] = {} }
  updates.each do |key, new_value|
    path = key_to_file[key]
    next unless path

    file_updates[path][key] = new_value
  end

  changed_keys = []
  file_updates.each do |path, key_values|
    ar_hash = file_to_ar_hash[path]
    key_values.each do |dotted_key, new_value|
      old_value = nil
      parts = dotted_key.split(".")
      current = ar_hash
      skip = false
      parts.each_with_index do |part, i|
        unless current.is_a?(Hash) && current.key?(part)
          skip = true
          break
        end
        if i == parts.size - 1
          old_value = current[part]
          current[part] = new_value
        else
          current = current[part]
        end
      end
      next if skip

      # Only report as changed if value actually changed
      changed_keys << { key: dotted_key, old: old_value, new: new_value, file: path } if old_value != new_value
    end

    next if dry_run

    full_data = file_to_full_data[path]
    full_data["ar"] = ar_hash
    File.write(path, YAML.dump(full_data))
  end

  changed_keys
end

def apply_missing_keys(updates, key_to_file, key_to_en_file, dry_run:, locales_dir:)
  added = []
  by_ar_path = Hash.new { |h, k| h[k] = {} }
  updates.each do |key, new_value|
    next if key_to_file[key]
    en_path = key_to_en_file[key]
    next unless en_path

    ar_path = en_file_to_ar_file(en_path)
    ar_path = File.expand_path(ar_path)
    by_ar_path[ar_path][key] = new_value
  end

  by_ar_path.each do |ar_path, key_values|
    full_data, ar_hash = load_ar_locale_file(ar_path)
    if full_data.nil?
      full_data = { "ar" => {} }
      ar_hash = full_data["ar"]
    end

    key_values.each do |dotted_key, new_value|
      deep_set_creating(ar_hash, dotted_key, new_value)
      added << { key: dotted_key, file: ar_path, new: new_value }
    end

    next if dry_run

    FileUtils.mkdir_p(File.dirname(ar_path))
    full_data["ar"] = ar_hash
    File.write(ar_path, YAML.dump(full_data))
  end

  added
end

def main
  file1_path, file2_path, dry_run, no_header, add_missing = parse_args
  skip_header = !no_header

  unless File.file?(file1_path)
    puts "Error: Keys file not found: #{file1_path}"
    usage
  end
  unless File.file?(file2_path)
    puts "Error: Clients file not found: #{file2_path}"
    usage
  end

  rails_root = File.expand_path(File.join(__dir__, ".."))
  locales_dir = File.join(rails_root, "config", "locales")

  puts "Reading keys file: #{file1_path}"
  puts "Reading clients file: #{file2_path}"
  updates = build_updates(file1_path, file2_path, skip_header: skip_header)
  puts "Matched #{updates.size} rows."

  locale_files = find_ar_locale_files(locales_dir)
  key_to_file, file_to_full_data, file_to_ar_hash = build_key_to_file_and_content(locale_files)

  applied = updates.count { |key, _| key_to_file[key] }
  skipped = updates.size - applied
  puts "Keys present in locale files: #{applied}. Keys not found in any ar locale: #{skipped}"

  if skipped.positive?
    missing = updates.keys.reject { |k| key_to_file[k] }
    puts "\nKeys not found in locale files (no update):"
    missing.first(20).each { |k| puts "  - #{k}" }
    puts "  ... and #{missing.size - 20} more" if missing.size > 20
    if add_missing
      key_to_en_file = build_key_to_en_file(locales_dir)
      addable = missing.count { |k| key_to_en_file[k] }
      puts "\n(With --add-missing: #{addable} of these exist in English and will be added to Arabic files.)"
    end
  end

  changed = apply_updates_and_save(
    file_to_full_data,
    file_to_ar_hash,
    key_to_file,
    updates,
    dry_run: dry_run
  )

  added = []
  if add_missing && skipped.positive?
    key_to_en_file = build_key_to_en_file(locales_dir)
    added = apply_missing_keys(
      updates,
      key_to_file,
      key_to_en_file,
      dry_run: dry_run,
      locales_dir: locales_dir
    )
  end

  puts "\n#{'[DRY RUN] ' if dry_run}Keys changed: #{changed.size}"
  changed.each do |c|
    puts "\n  #{c[:key]}"
    puts "    File: #{c[:file]}"
    puts "    Old: #{c[:old].inspect}"
    puts "    New: #{c[:new].inspect}"
  end

  if added.any?
    puts "\n#{'[DRY RUN] ' if dry_run}Keys added (missing in Arabic, created from English + client value): #{added.size}"
    added.each do |a|
      puts "\n  #{a[:key]}"
      puts "    File: #{a[:file]}"
      puts "    New: #{a[:new].inspect}"
    end
  end

  if add_missing
    key_to_en_file = build_key_to_en_file(locales_dir)
    not_in_en = updates.keys.reject { |k| key_to_file[k] || key_to_en_file[k] }
    if not_in_en.any?
      puts "\nKeys still not in any locale (not in English either): #{not_in_en.size}"
      not_in_en.first(10).each { |k| puts "  - #{k}" }
      puts "  ... and #{not_in_en.size - 10} more" if not_in_en.size > 10
    end
  end

  puts "\nDone."
end

main
