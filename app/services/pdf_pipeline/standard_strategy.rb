# frozen_string_literal: true

module PdfPipeline
  # Base strategy for standard-specific behavior (EFQM/KAQA, ISO 9001, Qiyas).
  # Subclasses override prompts, model names, keywords, and optional text normalization.
  class StandardStrategy
    class << self
      def for(standard_type, standard_name: nil)
        normalized = standard_type.to_s.downcase.gsub(/\s+/, "")
        if normalized.include?("qiyas")
          PdfPipeline::Strategies::QiyasStrategy.new(standard_type, standard_name: standard_name)
        elsif normalized.include?("iso9001")
          PdfPipeline::Strategies::Iso9001Strategy.new(standard_type, standard_name: standard_name)
        elsif normalized.include?("efqm") || normalized.include?("kaqa")
          PdfPipeline::Strategies::EfqmStrategy.new(standard_type, standard_name: standard_name)
        else
          PdfPipeline::Strategies::GenericStrategy.new(standard_type, standard_name: standard_name)
        end
      end
    end

    def initialize(standard_type, standard_name: nil)
      @standard_type = standard_type
      @standard_name = standard_name
    end

    attr_reader :standard_type, :standard_name

    def structure_extraction_model
      "qwen-extract-structure"
    end

    def checkpoint_extraction_model
      "qwen-extract-checkpoints"
    end

    def structure_prompt(chunk_text)
      <<~PROMPT
        Standard type: #{standard_type}

        Extract ONLY criteria and subcriteria that have explicit IDs/numbers in the text.

        RULES:
        - ONLY extract items with explicit numeric IDs (e.g., "Criterion 1", "1.1", "1a", etc.)
        - DO NOT invent IDs for bullet points or descriptive text
        - DO NOT create structure from unnumbered lists
        - If a criterion has no numbered subcriteria in the text, extract ONLY the criterion

        For each item found, extract:
        - id: The EXACT ID from the document (e.g., "1", "1.1", "1a")
        - parent_id: The ID of the parent (null for top-level criteria)
        - raw_text: The full text of that section

        TEXT:
        #{chunk_text}

        Return JSON with "blocks" array. Each block must have: id, parent_id, raw_text.
      PROMPT
    end

    def checkpoint_prompt(subcriterion_id, text)
      <<~PROMPT
        Extract checkpoints for ASSESSMENT subcriterion: #{subcriterion_id}

        IMPORTANT:
        - Look for "In practice, we find..." sections
        - Extract bullet points (–, •) that are assessment criteria
        - SKIP document sections like "Guiding Principles", "Use Cases", "Case Studies"
        - SKIP explanatory text about EFQM/the model itself

        TEXT:
        #{text}

        Return JSON with "checkpoints" array. Each checkpoint must have: id, parent_id, raw_text.
        Use sequential IDs: #{subcriterion_id}-1, #{subcriterion_id}-2, etc.
        Return empty array if no assessment checkpoints found (only document sections).
      PROMPT
    end

    def assessment_keywords
      [
        "In practice",
        "demonstrates sustainable performance",
        "outstanding organisation",
        "يتضمن هذا المعيار",
        "ويمكن أن يشمل ذلك ما يلي"
      ]
    end

    def toc_indicators
      ["فهرس المعايير", "إجمالي درجة", "Table of Contents", "Contents"]
    end

    def model_display_name
      case normalized_type
      when "efqm" then "EFQM Excellence Model 2025"
      when "iso9001" then "ISO 9001:2015"
      when "iso27001" then "ISO 27001:2013"
      when "kaqa" then "King Abdulaziz Quality Award"
      when "qiyas" then "Qiyas 2025 (Saudi Digital Transformation)"
      else standard_type.to_s
      end
    end

    # For translation: when document is in Arabic (e.g. KAQA), return "ar" so we translate ar→en.
    # When English (e.g. EFQM), return nil so we auto-detect from content.
    def document_source_language
      combined = (standard_type.to_s + " " + standard_name.to_s).downcase
      combined.include?("kaqa") || combined.include?("king abdulaziz") ? "ar" : nil
    end

    # Override to normalize text before structure extraction (e.g. bilingual ISO).
    def normalize_text(text, **)
      text
    end

    # Override if this standard can parse file directly (e.g. Qiyas XLSX).
    def parse_direct?(_file)
      false
    end

    # Override to return model hash when parse_direct?(file). Called only when parse_direct? is true.
    def parse_direct(_file, **_options)
      raise NotImplementedError, "#{self.class}#parse_direct must be implemented when parse_direct? is true"
    end

    private

    def normalized_type
      standard_type.to_s.upcase.gsub(/\s+/, "")
    end
  end
end
