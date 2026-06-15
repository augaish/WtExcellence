class PdfTextCleanupService
  def initialize(raw_text)
    @raw_text = raw_text.force_encoding("UTF-8")
  end

  def cleanup(text = nil)
    text ||= @raw_text
    cleaned = normalize_whitespace(text)
    cleaned = remove_non_characters(cleaned)
    cleaned
  end

  def chunk_by_pages(page_texts, pages_per_chunk: 2, overlap_chars: 200)
    chunks = []
    
    page_texts.each_slice(pages_per_chunk).with_index do |page_group, group_index|
      chunk_text = page_group.join("\n\n")
      
      if group_index > 0 && chunks.any?
        overlap_text = chunks.last[-overlap_chars..-1] || ""
        chunk_text = overlap_text + "\n\n" + chunk_text
      end
      
      chunks << chunk_text
    end
    
    chunks
  end

  private

  def normalize_whitespace(text)
    text = text.gsub(/[ \t]{2,}/, " ")
    text = text.gsub(/\n[ \t]+/, "\n")
    text = text.gsub(/[ \t]+\n/, "\n")
    text = text.gsub(/\n{3,}/, "\n\n")
    text
  end

  def remove_non_characters(text)
    allowed_symbols = /[•\-\–\—\•\▪\▫\*\u2022\u2023\u25E6\u2043\u2219]/
    arabic = /[\u0600-\u06FF]/
    english = /[a-zA-Z]/
    numbers = /[0-9]/
    punctuation = /[.,;:!?'"()\[\]{}\/\\\-\–\—\=\+\<\>\|@#\$%&\*_\s\n\t]/
    
    allowed_pattern = Regexp.union(allowed_symbols, arabic, english, numbers, punctuation)
    text.chars.select { |char| char.match?(allowed_pattern) }.join
  end
end

