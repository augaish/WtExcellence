# frozen_string_literal: true

module PdfPipeline
  module Strategies
    # Generic/other standards (not EFQM/KAQA, not ISO 9001, not Qiyas).
    # Uses two custom Ollama models you create with the general structure + checkpoint prompts.
    class GenericStrategy < PdfPipeline::StandardStrategy
      STRUCTURE_MODEL = "qwen-extract-structure-generic"
      CHECKPOINT_MODEL = "qwen-extract-checkpoints-generic"

      def structure_extraction_model
        STRUCTURE_MODEL
      end

      def checkpoint_extraction_model
        CHECKPOINT_MODEL
      end

      def structure_prompt(chunk_text)
        standard_label = standard_name.presence || standard_type
        <<~PROMPT.strip
          Standard: #{standard_label}

          Extract every numbered clause. When you extract subcriteria (e.g. 1.1, 1.2), always include their parent criterion (e.g. id "1", raw_text "Purpose, Vision & Strategy" when "Criterion 1" appears). Treat 3.1 and 3.10 as different clauses (extract both). If the clause number is on one line and the title on the next line, pair them (e.g. line "3.1" then line "advisory notice" → id "3.1", raw_text "advisory notice"). Do NOT extract document-structure sections: Glossary, Terms and definitions, References, Bibliography, Table of contents, Foreword, Introduction (as section title only), Index. Do NOT extract scoring/diagnostic/methodology sections (e.g. RADAR, "Diagnostic Tool", "Scoring Analysis", "AssessBase", or 3.1, 3.2 under such a section)—extract only normative criteria. Do not extract from a Contents/TOC list; only from body content. Do NOT extract Introduction, Case Studies, Use Cases, Guiding Principles, "About", or similar narrative sections as criteria—only the actual assessment criteria. When the same numbers appear in intro/TOC and in the criteria section, use only the criteria section for id and raw_text. Skip e.g. "6 Glossary". id = criterion/subcriterion number only, never weight/points: in tables with weight (الوزن), use id "1", "1-1", "2", "2-1", not 150, 25, 100. For "المعيار الأول" use id "1"; for "1-1" use parent_id "1". parent_id must be derived only from the clause id: for id "4.2" or "1-1" parent_id is "4" or "1"; do not use other numbers from the document (e.g. "2" from "2 The EFQM Model").

          TEXT:
          #{chunk_text}

          For each clause, output raw_text_en and raw_text_ar: if the clause text is only in English put it in raw_text_en and raw_text_ar as "". If only in Arabic put it in raw_text_ar and raw_text_en as "". If the document shows both languages (e.g. bilingual heading), put each in its field. This allows skipping translation when both are present.
          If this chunk has no normative criteria (e.g. only Glossary, definition list, References), return exactly {"blocks": []}. Do not include a block for "6 Glossary" or similar — return empty blocks instead.
          Return valid JSON only, no markdown code fences, no explanations. Output format: {"blocks": [{"id": "...", "parent_id": ... or null, "raw_text_en": "...", "raw_text_ar": "..."}, ...]} or {"blocks": []} when there are no clauses to extract. Use "" for a language when not present.
        PROMPT
      end

      def checkpoint_prompt(subcriterion_id, text)
        <<~PROMPT.strip
          Extract requirements for clause/criterion: #{subcriterion_id}

          TEXT:
          #{text}

          Return valid JSON only, no markdown code fences, no explanations. Output format: {"checkpoints": [{"id": "#{subcriterion_id}-1", "parent_id": "#{subcriterion_id}", "raw_text": "..."}, ...]} Use sequential IDs #{subcriterion_id}-1, #{subcriterion_id}-2, etc. Return {"checkpoints": []} if no requirements found.
        PROMPT
      end

      # Broader keywords for generic standards (modal verbs, common phrases)
      def assessment_keywords
        [
          "shall", "must", "is required to", "يجب", "ينبغي", "يُشترط",
          "determine", "ensure", "establish", "document",
          "a)", "b)", "c)", "أ - ", "ب - ", "ت - "
        ]
      end
    end
  end
end
