# frozen_string_literal: true

module PdfPipeline
  # Finds page chunks relevant to a given subcriterion for checkpoint extraction.
  class RelevantPagesFinder
    def initialize(strategy)
      @strategy = strategy
    end

    def find(sub_id, sub_text, page_texts)
      relevant_pages = []
      toc_indicators = @strategy.toc_indicators
      assessment_keywords = @strategy.assessment_keywords
      reversed_id = reversed_id_for(sub_id)

      page_texts.each_with_index do |page, idx|
        next if toc_indicators.any? { |indicator| page.include?(indicator) }

        has_id = page.include?(sub_id) || (reversed_id && page.include?(reversed_id))
        has_assessment = assessment_keywords.any? { |kw| page.include?(kw) }
        has_sub_text = sub_text && page.include?(sub_text[0..50])

        if (has_id && has_assessment) || has_sub_text
          relevant_pages << page
          relevant_pages << page_texts[idx + 1] if idx + 1 < page_texts.length
          break if relevant_pages.length >= 4
        end
      end

      # Fallback: broader search
      if relevant_pages.empty?
        page_texts.each_with_index do |page, idx|
          next if toc_indicators.any? { |indicator| page.include?(indicator) }
          has_id = page.include?(sub_id) || (reversed_id && page.include?(reversed_id))
          has_text = sub_text && page.include?(sub_text[0..50])
          if has_id || has_text
            relevant_pages << page
            relevant_pages << page_texts[idx + 1] if idx + 1 < page_texts.length
            break if relevant_pages.length >= 3
          end
        end
      end

      relevant_pages.empty? ? page_texts.join("\n\n") : relevant_pages.join("\n\n")
    end

    private

    def reversed_id_for(sub_id)
      return nil unless sub_id.include?("-")
      parts = sub_id.split("-")
      return nil unless parts.length == 2 && parts.all? { |p| p.match?(/^\d+$/) }
      "#{parts[1]}-#{parts[0]}"
    end
  end
end
