# frozen_string_literal: true

module PdfPipeline
  module Strategies
    # Qiyas 2025: different models/prompts; can parse XLSX directly.
    class QiyasStrategy < PdfPipeline::StandardStrategy
      QIYAS_KEYWORDS = [
        " - ",
        "أ‌ - ",
        "ب‌ - ",
        "بحيث تشمل",
        "التحول الرقمي"
      ].freeze

      def structure_extraction_model
        "qwen-extract-structure-qiyas2025"
      end

      def checkpoint_extraction_model
        "qwen-extract-checkpoints-qiyas2025"
      end

      def structure_prompt(chunk_text)
        <<~PROMPT
          Standard type: Qiyas 2025 (Saudi Digital Transformation)

          TEXT:
          #{chunk_text}

          Return JSON with "blocks" array. Each block must have: id, parent_id, raw_text.
        PROMPT
      end

      def checkpoint_prompt(subcriterion_id, text)
        <<~PROMPT
          Extract requirements (checkpoints) for Qiyas 2025 criterion: #{subcriterion_id}

          TEXT:
          #{text}

          Return JSON with "checkpoints" array. Each checkpoint must have: id, parent_id, raw_text.
          Use sequential IDs: #{subcriterion_id}-1, #{subcriterion_id}-2, etc.
          Return empty array if no requirements are found.
        PROMPT
      end

      def assessment_keywords
        super + QIYAS_KEYWORDS
      end

      def parse_direct?(file)
        file_xlsx?(file)
      end

      def parse_direct(file, model_display_name:, **options)
        PdfPipeline::QiyasXlsxParser.new(
          file,
          model_display_name: model_display_name,
          **options
        ).parse
      end

      private

      def file_xlsx?(file)
        name = if file.respond_to?(:filename)
          file.filename.to_s
        elsif file.respond_to?(:original_filename)
          file.original_filename.to_s
        elsif file.respond_to?(:path)
          File.basename(file.path)
        else
          ""
        end
        name.downcase.end_with?(".xlsx")
      end
    end
  end
end
