# frozen_string_literal: true

module PdfPipeline
  module Strategies
    # ISO 9001: different models/prompts and bilingual text normalization.
    class Iso9001Strategy < PdfPipeline::StandardStrategy
      def structure_extraction_model
        "qwen-extract-structure-iso9001"
      end

      def checkpoint_extraction_model
        "qwen-extract-checkpoints-iso9001"
      end

      def structure_prompt(chunk_text)
        <<~PROMPT
          Standard type: ISO 9001

          TEXT:
          #{chunk_text}

          Return JSON with "blocks" array. Each block must have: id, parent_id, raw_text.
        PROMPT
      end

      def checkpoint_prompt(subcriterion_id, text)
        <<~PROMPT
          Extract requirements (checkpoints) for ISO 9001 clause: #{subcriterion_id}

          TEXT:
          #{text}

          Return JSON with "checkpoints" array. Each checkpoint must have: id, parent_id, raw_text.
          Use sequential IDs: #{subcriterion_id}-1, #{subcriterion_id}-2, etc.
          Return empty array if no requirements are found.
        PROMPT
      end

      def normalize_text(text, **options)
        PdfPipeline::BilingualNormalizer.new(options).normalize(text)
      end
    end
  end
end
