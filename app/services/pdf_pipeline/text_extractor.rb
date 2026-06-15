# frozen_string_literal: true

module PdfPipeline
  # Extracts and cleans text from PDF/XLSX (via Tika) and splits into page-sized chunks.
  class TextExtractor
    require "open3"

    def initialize(file)
      @file = file
    end

    def extract_full_text
      path = resolve_path
      stdout, stderr, status = Open3.capture3("tika", "--text", path)
      raise "Tika extraction failed: #{stderr}" unless status.success?
      stdout
    end

    def clean(text)
      return "" if text.nil?

      t = text.dup

      # 1) Normalize newlines (Windows/Mac -> Unix)
      t.gsub!(/\r\n?/, "\n")

      # 2) Replace tabs with spaces
      t.gsub!(/\t/, " ")

      # 3) Remove ZERO-WIDTH / bidi / invisible unicode chars (common OCR/PDF junk)
      t.gsub!(/[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]/, "")

      # 4) Remove control characters except newline
      t.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")

      # 5) Normalize common unicode punctuation variants
      t.tr!("“”", "\"")
      t.tr!("‘’", "'")
      t.tr!("–—", "-")

      # 6) Normalize bullets into a single bullet (optional but helpful)
      t.gsub!(/[▪◦○●]/, "•")

      # 7) Collapse multiple spaces (but keep newlines)
      t.gsub!(/[ ]{2,}/, " ")

      # 8) Collapse too many blank lines
      t.gsub!(/\n{3,}/, "\n\n")

      # 9) Trim trailing spaces on each line (helps structure detection)
      t.gsub!(/[ \t]+\n/, "\n")

      # 10) Strip overall leading/trailing whitespace
      t.strip!

      t
    end

    def split_into_pages(text, chars_per_page: 6000)
      pages = []
      current_pos = 0

      while current_pos < text.length
        chunk_end = [current_pos + chars_per_page, text.length].min
        pages << text[current_pos...chunk_end].strip
        current_pos = chunk_end
      end

      pages.reject(&:empty?)
    end

    private

    def resolve_path
      if @file.respond_to?(:path)
        @file.path
      elsif @file.respond_to?(:tempfile)
        @file.tempfile.path
      else
        ext = @file.respond_to?(:filename) ? @file.filename.extension_with_delimiter : ".pdf"
        ext = ".pdf" if ext.blank?
        temp_file = Tempfile.new(["extract", ext])
        temp_file.binmode
        @file.download { |chunk| temp_file.write(chunk) }
        temp_file.close
        temp_file.path
      end
    end
  end
end
