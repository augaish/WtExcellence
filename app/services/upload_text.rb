# The readable text of a Library file, so the assistant can answer from what
# the evidence actually says rather than from its file name. PDFs, Word
# documents and plain text are read; anything else yields nil. Cached by the
# file's checksum, so a document is read once however often it is asked about.
module UploadText
  module_function

  MAX_CHARS = 4000

  def for(upload, max_chars: MAX_CHARS)
    blob = upload.file.attached? ? upload.file.blob : nil
    return nil if blob.nil?

    text = Rails.cache.fetch([ "upload_text", blob.checksum ], expires_in: 7.days) { extract(blob) }
    text.presence&.truncate(max_chars)
  rescue => e
    Rails.logger.warn "UploadText failed for #{upload.id}: #{e.class}: #{e.message}"
    nil
  end

  def extract(blob)
    blob.open do |file|
      case
      when blob.content_type == "application/pdf" || blob.filename.extension == "pdf"
        PDF::Reader.new(file.path).pages.first(20).map(&:text).join("\n")
      when blob.filename.extension == "docx"
        Zip::File.open(file.path) do |zip|
          xml = zip.find_entry("word/document.xml")&.get_input_stream&.read.to_s
          xml.gsub(%r{</w:p>}, "\n").gsub(/<[^>]+>/, "").then { |t| CGI.unescapeHTML(t) }
        end
      when blob.content_type.to_s.start_with?("text/") || %w[txt csv md].include?(blob.filename.extension)
        File.read(file.path, 200_000).to_s.force_encoding("UTF-8").scrub
      end
    end.to_s.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
  end
end
