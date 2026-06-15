# frozen_string_literal: true

module PdfPipeline
  # Parses Qiyas 2025 XLSX: Column A = code, B = axis, C = standard name, D = requirements.
  # Returns model hash in same format as ModelAssembler for translation and persistence.
  class QiyasXlsxParser
    require "roo"

    include PdfPipeline::IdHelper

    def initialize(file, model_display_name:, pipeline_run_id: nil, debug_save: false)
      @file = file
      @model_display_name = model_display_name
      @pipeline_run_id = pipeline_run_id
      @debug_save = debug_save
    end

    def parse
      path = resolve_xlsx_path
      xlsx = Roo::Spreadsheet.open(path)
      sheet = choose_sheet(xlsx)
      last_row = sheet.last_row.to_i

      if last_row < 1
        return empty_model
      end

      rows = collect_rows(sheet, last_row)
      save_raw_sample(rows.first(25).map.with_index { |r, i| { row: i + 1, code: r[:code], axis: r[:axis], standard_name: r[:standard_name], requirement: r[:requirement] } }) if @debug_save

      by_code = group_by_code(rows)
      all_codes_set = infer_parent_codes(by_code, rows)
      codes = all_codes_set.to_a.sort_by { |k| normalize_id_for_sorting(k) }
      parent_of = build_parent_map(codes)

      root_name_ar = "معيار قياس التحول الرقمي"
      subcriteria = build_criterion_tree("5", by_code, codes, parent_of, root_name_ar)
      criteria = [
        "id" => 5,
        "points" => 0,
        "name_ar" => root_name_ar,
        "name_en" => "",
        "subcriteria" => subcriteria
      ]

      total_checkpoints = subcriteria.sum { |s| count_checkpoints(s) }
      Rails.logger.info "Parsed Qiyas XLSX: #{codes.size} codes, #{total_checkpoints} checkpoints"

      result = {
        "model" => {
          "name_en" => @model_display_name,
          "name_ar" => "",
          "award" => "",
          "total_points" => 1000,
          "principles" => [],
          "criteria" => criteria
        }
      }

      save_parsed_tree(result) if @debug_save
      result
    end

    private

    def empty_model
      {
        "model" => {
          "name_en" => @model_display_name,
          "name_ar" => "",
          "award" => "",
          "total_points" => 1000,
          "principles" => [],
          "criteria" => []
        }
      }
    end

    def resolve_xlsx_path
      if @file.respond_to?(:path)
        @file.path
      elsif @file.respond_to?(:tempfile)
        @file.tempfile.path
      else
        temp_file = Tempfile.new(["qiyas", ".xlsx"])
        temp_file.binmode
        @file.download { |chunk| temp_file.write(chunk) }
        temp_file.close
        temp_file.path
      end
    end

    def choose_sheet(xlsx)
      names = xlsx.sheets.map(&:to_s)
      found = names.find { |n| n =~ /action|plan|خطة|المعيار|معيار/i }
      found ? xlsx.sheet(found) : xlsx.sheet(0)
    end

    def safe_cell(row, index)
      return nil unless row.is_a?(Array) && row[index]
      cell = row[index]
      cell.respond_to?(:value) ? cell.value : cell
    end

    def normalize_qiyas_code(val)
      return "" if val.nil?
      val = val.value if val.respond_to?(:value)
      return "" if val.nil?
      s = val.to_s.strip
      return s unless val.is_a?(Numeric)
      return val.to_i.to_s if val == val.to_i
      parts = val.to_s.split(".")
      return val.to_s if parts.size != 2
      int_part = parts[0]
      dec_part = parts[1].to_s
      return "#{int_part}.#{dec_part}" if dec_part.length <= 1
      "#{int_part}.#{dec_part.chars.join('.')}"
    end

    def collect_rows(sheet, last_row)
      rows = []
      1.upto(last_row) do |i|
        raw = sheet.row(i)
        code_str = normalize_qiyas_code(safe_cell(raw, 0))
        next if code_str.blank?
        next unless code_str.match?(/^\d+(\.\d+)*$/)
        rows << {
          code: code_str,
          axis: (safe_cell(raw, 1) || "").to_s.strip,
          standard_name: (safe_cell(raw, 2) || "").to_s.strip,
          requirement: (safe_cell(raw, 3) || "").to_s.strip
        }
      end
      rows
    end

    def group_by_code(rows)
      by_code = {}
      rows.each do |r|
        c = r[:code]
        by_code[c] ||= { axis: r[:axis], standard_name: r[:standard_name], requirements: [] }
        by_code[c][:requirements] << r[:requirement] if r[:requirement].present?
      end
      by_code
    end

    def infer_parent_codes(by_code, rows)
      codes_from_sheet = by_code.keys.uniq
      all_codes_set = Set.new(codes_from_sheet)
      codes_from_sheet.each do |c|
        parts = c.split(".")
        next if parts.size <= 1
        (1...parts.size).each do |len|
          parent = parts[0, len].join(".")
          all_codes_set.add(parent)
          next if by_code.key?(parent)
          first_child = rows.find { |r| r[:code].start_with?(parent + ".") }
          by_code[parent] = {
            axis: first_child&.dig(:axis).to_s,
            standard_name: "",
            requirements: []
          }
        end
      end
      all_codes_set
    end

    def build_parent_map(codes)
      parent_of = {}
      codes.each do |c|
        parts = c.split(".")
        parent_of[c] = parts.size == 1 ? nil : parts[0..-2].join(".")
      end
      parent_of
    end

    def build_criterion_tree(code, by_code, all_codes, parent_of, name_ar)
      children = all_codes.select { |c| parent_of[c] == code }.sort_by { |c| normalize_id_for_sorting(c) }
      return [] if children.empty?

      children.map do |child_code|
        info = by_code[child_code] || {}
        child_children = all_codes.select { |c| parent_of[c] == child_code }
        is_leaf = child_children.empty?
        name = info[:standard_name].presence || info[:axis].presence || child_code

        sub = {
          "id" => child_code,
          "points" => 0,
          "name_ar" => name,
          "name_en" => ""
        }

        if is_leaf
          reqs = info[:requirements] || []
          sub["checkpoints"] = reqs.each_with_index.map do |text, i|
            { "id" => "#{child_code}-#{i + 1}", "text_ar" => text.to_s.strip, "text_en" => "" }
          end
          sub["subcriteria"] = []
        else
          sub["subcriteria"] = build_criterion_tree(child_code, by_code, all_codes, parent_of, info[:axis].presence || name)
          sub["checkpoints"] = []
        end
        sub
      end
    end

    def count_checkpoints(node)
      (node["checkpoints"]&.size || 0) + (node["subcriteria"]&.sum { |n| count_checkpoints(n) } || 0)
    end

    def save_raw_sample(sample)
      return unless @debug_save
      dir = @pipeline_run_id ? Rails.root.join("tmp", "pipeline_chunks", @pipeline_run_id) : Rails.root.join("tmp", "qiyas_parsed")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("qiyas_xlsx_raw_sample.json"), JSON.pretty_generate(sample))
      Rails.logger.info "  Debug: saved Qiyas raw sample"
    rescue => e
      Rails.logger.warn "  Could not save raw sample: #{e.message}"
    end

    def save_parsed_tree(model_hash)
      return unless @debug_save
      dir = @pipeline_run_id ? Rails.root.join("tmp", "pipeline_chunks", @pipeline_run_id) : Rails.root.join("tmp", "qiyas_parsed")
      FileUtils.mkdir_p(dir)
      path = dir.join("qiyas_xlsx_tree_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")
      File.write(path, JSON.pretty_generate(model_hash))
      Rails.logger.info "  Debug: saved Qiyas tree to #{path}"
    rescue => e
      Rails.logger.warn "  Could not save Qiyas parsed tree: #{e.message}"
    end
  end
end
