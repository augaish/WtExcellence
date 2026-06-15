# frozen_string_literal: true

module PdfPipeline
  # Assembles the final model hash from structure + checkpoint blocks.
  class ModelAssembler
    include PdfPipeline::IdHelper

    def initialize(model_display_name)
      @model_display_name = model_display_name
    end

    def assemble(all_blocks)
      criteria_blocks = all_blocks
        .select { |b| b["parent_id"].blank? }
        .sort_by { |b| normalize_id_for_sorting(b["id"]) }

      criteria = criteria_blocks.map do |criterion|
        assemble_criterion(criterion, all_blocks)
      end

      {
        "model" => {
          "name_en" => @model_display_name,
          "name_ar" => "",
          "award" => "",
          "total_points" => 1000,
          "principles" => [],
          "criteria" => criteria
        }
      }
    end

    def self.detect_language(text)
      text.match?(/[\u0600-\u06FF]/) ? "ar" : "en"
    end

    def self.extract_title(raw_text)
      return "" unless raw_text
      lines = raw_text.split("\n").map(&:strip).reject(&:empty?)
      return "" if lines.empty?
      title = lines.first
        .gsub(/^\d+[\.\-]\s*/, "")
        .gsub(/^(Criterion|Clause)\s*\d+[\.\:]?\s*/i, "")
      title[0..200]
    end

    private

    def assemble_criterion(criterion, all_blocks)
      criterion_id = criterion["id"]
      child_subcriteria = all_blocks
        .select { |b| b["parent_id"] == criterion_id }
        .sort_by { |b| normalize_id_for_sorting(b["id"]) }

      subcriteria = child_subcriteria.map { |sub| assemble_subcriterion(sub, all_blocks) }
      name_en, name_ar = title_en_and_ar(criterion)

      transformed_id = criterion_id.to_s.match?(/^\d+$/) ? criterion_id.to_i : transform_id_format(criterion_id)
      { "id" => transformed_id, "points" => 0, "name_en" => name_en, "name_ar" => name_ar, "subcriteria" => subcriteria }
    end

    def assemble_subcriterion(subcriterion, all_blocks)
      sub_id = subcriterion["id"]
      nested = all_blocks
        .select { |b| b["parent_id"] == sub_id && !checkpoint?(b) }
        .sort_by { |b| normalize_id_for_sorting(b["id"]) }

      checkpoints = all_blocks
        .select { |cp| checkpoint?(cp) && cp["parent_id"] == sub_id }
        .sort_by { |cp| normalize_id_for_sorting(cp["id"]) }
        .map { |cp| checkpoint_to_result(cp) }

      name_en, name_ar = title_en_and_ar(subcriterion)
      base = {
        "id" => transform_id_format(sub_id),
        "points" => 0,
        "name_en" => name_en,
        "name_ar" => name_ar,
        "checkpoints" => checkpoints
      }
      base["subcriteria"] = nested.map { |n| assemble_subcriterion(n, all_blocks) } if nested.any?
      base
    end

    # When block has raw_text_en/raw_text_ar (generic pipeline), use both; else use raw_text + language detection.
    # When both en and ar are blank (e.g. LLM missed the title), fall back to raw_text or "Clause {id}".
    def title_en_and_ar(block)
      if block.key?("raw_text_en") || block.key?("raw_text_ar")
        en = self.class.extract_title(block["raw_text_en"].to_s)
        ar = self.class.extract_title(block["raw_text_ar"].to_s)
        if en.present? || ar.present?
          [en, ar]
        elsif block["raw_text"].present?
          title = self.class.extract_title(block["raw_text"].to_s)
          lang = self.class.detect_language(title)
          lang == "ar" ? ["", title] : [title, ""]
        else
          fallback = "Clause #{block['id']}"
          [fallback, ""]
        end
      else
        title = self.class.extract_title(block["raw_text"].to_s)
        lang = self.class.detect_language(title)
        lang == "ar" ? ["", title] : [title, ""]
      end
    end

    def checkpoint_to_result(cp)
      # Checkpoints from stage 2 have raw_text only (generic checkpoint prompt unchanged)
      text = cp["raw_text"] || ""
      lang = self.class.detect_language(text)
      text_en = lang == "ar" ? "" : text
      text_ar = lang == "ar" ? text : ""
      { "id" => transform_id_format(cp["id"]), "text_en" => text_en, "text_ar" => text_ar }
    end

    # Checkpoint = requirement under a subcriterion (id like "4.1-1" or "1-1-1"). Not "1-1" with parent "1" (that's N-M subcriterion).
    def checkpoint?(block)
      pid = block["parent_id"].to_s
      return false if pid.empty?
      id = block["id"].to_s
      return false unless id.start_with?("#{pid}-") && id[pid.length + 1..].match?(/^\d+$/)
      # Parent must be a subcriterion (has dot or hyphen), so "4.1-1" is checkpoint, "1-1" with parent "1" is not
      pid.include?(".") || pid.include?("-")
    end
  end
end
