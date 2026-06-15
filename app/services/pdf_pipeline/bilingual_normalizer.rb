# frozen_string_literal: true

module PdfPipeline
  # Normalizes bilingual text (e.g. ISO 9001 parallel columns) to a single language stream
  # so structure/checkpoint extraction does not see duplicates.
  class BilingualNormalizer
    def initialize(options = {})
      @prefer = (options[:bilingual_prefer_language] || "en").to_s.downcase
      @threshold = (options[:bilingual_standalone_threshold] || 15).to_i
      @min_ratio = (options[:bilingual_min_script_ratio] || 0.30).to_f
      @min_ratio = 0.01 if @min_ratio <= 0 || @min_ratio > 1
    end

    def normalize(text)
      return text if text.blank?

      has_arabic = text.match?(/\p{Arabic}/)
      has_latin = text.match?(/[a-zA-Z]/)
      return text unless has_arabic && has_latin

      keep_arabic = (@prefer == "ar")
      lines = text.split("\n")
      tags = lines.map { |line| tag_line(line, keep_arabic) }
      keep_other_ranges = find_standalone_other_ranges(tags)
      keep_index = ->(i) { keep_other_ranges.any? { |r| r.cover?(i) } }

      kept = lines.each_with_index.select do |_line, i|
        tags[i] == :empty || tags[i] == :preferred || keep_index.call(i)
      end.map(&:first)

      result = kept.join("\n").gsub(/\n{3,}/, "\n\n").strip
      Rails.logger.info "  Bilingual ISO 9001: normalized to #{@prefer} (+ #{keep_other_ranges.size} standalone #{@prefer == 'en' ? 'Arabic' : 'English'} section(s)) (#{lines.size} → #{kept.size} lines)"
      result
    end

    private

    def tag_line(line, keep_arabic)
      return :empty if line.strip.empty?

      line_arabic_count = line.scan(/\p{Arabic}/).size
      line_latin_count = line.scan(/[a-zA-Z]/).size
      total_script = line_latin_count + line_arabic_count

      if total_script.zero?
        line_has_arabic = false
        line_has_latin = false
      else
        line_has_latin = (line_latin_count.to_f / total_script) >= @min_ratio
        line_has_arabic = (line_arabic_count.to_f / total_script) >= @min_ratio
      end

      if keep_arabic
        line_has_arabic ? :preferred : :other
      else
        line_has_latin ? :preferred : :other
      end
    end

    def find_standalone_other_ranges(tags)
      keep_other_ranges = []
      in_run = false
      run_length = 0
      run_start = nil

      tags.each_with_index do |tag, i|
        if tag == :other
          if in_run
            run_length += 1
          else
            in_run = true
            run_start = i
            run_length = 1
          end
        else
          keep_other_ranges << (run_start..(i - 1)) if in_run && run_length >= @threshold
          in_run = false
        end
      end
      keep_other_ranges << (run_start..(tags.length - 1)) if in_run && run_length >= @threshold
      keep_other_ranges
    end
  end
end
