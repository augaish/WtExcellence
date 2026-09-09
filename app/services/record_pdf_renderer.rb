# Prints the governed document to PDF with headless Chromium: the same page a
# reader sees in the browser, which is already laid out for A4 and reads
# right-to-left for Arabic, so the PDF cannot say something different.
#
# Chromium is found through CHROMIUM_BIN or the usual names. Where it is not
# installed (tests, a developer machine) render returns nil and the caller
# carries on without a file rather than failing the publication.
class RecordPdfRenderer
  CANDIDATES = %w[chromium chromium-browser google-chrome google-chrome-stable].freeze

  def self.render(record, locale: I18n.locale)
    new(record, locale: locale).render
  end

  def self.stylesheet
    path = Rails.root.join("app/assets/builds/tailwind.css")
    # Read as UTF-8 whatever the process locale says, or the inlined sheet
    # cannot be joined to the page's own text.
    path.exist? ? path.read(encoding: "UTF-8").scrub : ""
  end

  def self.binary
    explicit = ENV["CHROMIUM_BIN"].presence
    return explicit if explicit && File.executable?(explicit)

    CANDIDATES.map { |name| `which #{name} 2>/dev/null`.strip }.find(&:present?)
  end

  def self.available?
    binary.present?
  end

  def initialize(record, locale: I18n.locale)
    @record = record
    @locale = locale
  end

  def render
    binary = self.class.binary
    return nil if binary.blank?

    Dir.mktmpdir("record-pdf") do |dir|
      html_path = File.join(dir, "document.html")
      pdf_path = File.join(dir, "document.pdf")
      File.write(html_path, html)

      ok = system(binary, "--headless=new", "--no-sandbox", "--disable-gpu", "--no-pdf-header-footer",
        "--print-to-pdf=#{pdf_path}", "file://#{html_path}", out: File::NULL, err: File::NULL)
      return nil unless ok && File.exist?(pdf_path)

      File.binread(pdf_path)
    end
  rescue => e
    Rails.logger.warn "PDF render failed for record #{@record.id}: #{e.class}: #{e.message}"
    nil
  end

  def html
    I18n.with_locale(@locale) do
      ApplicationController.render(
        template: "dashboard/pp_records/document",
        layout: "document",
        assigns: { document: RecordDocument.new(@record, locale: @locale), record: @record, inline_css: true }
      )
    end
  end

  def filename
    base = @record.code.presence || @record.display_title(@locale).presence || "document"
    "#{base.to_s.gsub(/[^\w\-.]+/, '_')}-#{@locale}.pdf"
  end
end
