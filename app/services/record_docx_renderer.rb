# Writes a governed document as a .docx file.
#
# A .docx is a zip of XML parts, so this writes WordprocessingML directly rather
# than through a builder gem. That is a deliberate choice: the builders available
# handle right-to-left text poorly, and a Word file that renders Arabic
# backwards is worse than the PDF the browser already produces. Writing the XML
# means bidi can be set where it actually belongs — on the section, on every
# paragraph, on every run, and on tables as bidiVisual so columns run right to
# left as a reader expects.
#
# It consumes RecordDocument, the same structure the on-screen document uses, so
# the two cannot describe different things.
class RecordDocxRenderer
  # Twentieths of a point, which is how Word measures nearly everything.
  HEADING_SIZE = 28
  TITLE_SIZE = 44
  BODY_SIZE = 20
  SMALL_SIZE = 16

  NAMESPACE = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'.freeze

  def self.render(document)
    new(document).render
  end

  def initialize(document)
    @document = document
    @locale = document.locale
    @rtl = document.locale.to_s == "ar"
    @primary = (document.cover[:palette]&.primary || BrandPalette::DEFAULT_PRIMARY).delete_prefix("#")
  end

  attr_reader :document, :locale, :primary

  def rtl?
    @rtl
  end

  # The finished file as a binary string, ready to send.
  def render
    buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
      { "[Content_Types].xml" => content_types,
        "_rels/.rels" => package_rels,
        "word/_rels/document.xml.rels" => document_rels,
        "word/styles.xml" => styles,
        "word/document.xml" => document_xml }.each do |name, contents|
        zip.put_next_entry(name)
        zip.write(contents)
      end
    end

    buffer.string
  end

  # A filename a reader can recognise on disk, with anything a filesystem
  # dislikes removed.
  def filename
    base = [ document.cover[:code], document.cover[:title] ].compact_blank.join(" - ")
    "#{base.gsub(/[^\p{Word}\s.-]/u, '').strip.squeeze(' ')}.docx"
  end

  private

  def document_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document #{NAMESPACE}>
        <w:body>
          #{cover_xml}
          #{sections_xml}
          #{section_properties}
        </w:body>
      </w:document>
    XML
  end

  def cover_xml
    cover = document.cover
    parts = []
    if cover[:draft]
      parts << paragraph(I18n.t("record_document.cover.draft", stage: cover[:stage_label], locale: locale), size: BODY_SIZE, color: "B45309", bold: true)
    end
    parts << paragraph(cover[:type_label], size: BODY_SIZE, color: primary, bold: true)
    parts << paragraph(cover[:title], size: TITLE_SIZE, bold: true)
    parts << paragraph(cover[:company_name], size: BODY_SIZE, color: "797C81")

    rows = {
      "code" => cover[:code],
      "owner" => cover[:owner],
      "version" => cover[:version],
      "effective_date" => format_value(cover[:effective_date]),
      "publish_date" => format_value(cover[:published_at]),
      "review_date" => format_value(cover[:review_date]),
      "classification" => cover[:classification],
      "counterparty" => cover[:counterparty]
    }.compact_blank

    parts << spacer
    parts << two_column_table(rows.map { |key, value| [ translate("record_document.cover.#{key}"), value.to_s ] })
    parts.join("\n")
  end

  def sections_xml
    document.sections.each_with_index.map do |section, index|
      [ page_break, heading("#{index + 1}. #{section.title}"), section_body(section) ].join("\n")
    end.join("\n")
  end

  def section_body(section)
    case section.kind
    when :prose then paragraph(section.payload.to_s)
    when :fields then two_column_table(field_rows(section.payload))
    when :matrix then matrix_table(section.payload)
    when :executive_matrix then executive_matrix_table(section.payload)
    when :diagram then paragraph(translate("record_document.diagram_omitted"), size: SMALL_SIZE, color: "797C81")
    when :table then section_table(section)
    else ""
    end
  end

  def field_rows(payload)
    payload.map { |key, value| [ translate("record_document.fields.#{key}", key.to_s.humanize), value.to_s ] }
  end

  def section_table(section)
    columns = RecordDocumentHelper::TABLE_COLUMNS.fetch(section.key, section.payload.first&.keys || [])
    headers = columns.map { |column| translate("record_document.columns.#{column}", column.to_s.humanize) }
    rows = section.payload.map { |row| columns.map { |column| cell_value(row, column) } }

    table(headers, rows)
  end

  def cell_value(row, column)
    key = RecordDocumentHelper::CELL_KEYS.fetch(column, column)
    return approval_status(row) if column == :status && row.key?(:received)

    format_value(row[key])
  end

  def approval_status(row)
    translate(row[:received] ? "record_document.approval_received" : "record_document.approval_pending")
  end

  def matrix_table(rows)
    headers = [ translate("record_document.columns.item"), translate("record_document.columns.decision") ] +
      AuthorityLevel::KEYS.map { |level| AuthorityLevel.label(level, locale) }

    body = rows.map do |row|
      [ row[:item].to_s, row[:decision].to_s ] + AuthorityLevel::KEYS.map do |level|
        holders = row[:assignments][level]
        next "-" if holders.blank?

        holders.map { |holder| [ holder[:holder], holder[:condition].presence && "(#{holder[:condition]})" ].compact.join(" ") }.join("; ")
      end
    end

    table(headers, body)
  end

  def executive_matrix_table(rows)
    headers = %w[category number authority].map { |c| translate("record_document.columns.#{c}") } +
      AuthorityLevel::KEYS.map { |level| AuthorityLevel.label(level, locale) }

    body = rows.map do |row|
      [ row[:category].to_s, row[:number].to_s, row[:authority].to_s ] +
        AuthorityLevel::KEYS.map do |level|
          holders = row[:assignments][level]
          next "-" if holders.blank?

          holders.map { |h| [ h[:holder], h[:condition].presence && "(#{h[:condition]})" ].compact.join(" ") }.join("; ")
        end
    end

    table(headers, body)
  end

  def format_value(value)
    return "" if value.nil?
    return I18n.l(value.to_date, format: :document, locale: locale) if value.is_a?(Date) || value.is_a?(Time)

    value.to_s
  end

  # --- WordprocessingML building blocks ---------------------------------------

  # Bidi belongs on the paragraph; rtl belongs on the run. Setting only one of
  # them leaves Word guessing, and it guesses wrongly for mixed content.
  def paragraph(text, size: BODY_SIZE, bold: false, color: nil, spacing_after: 120)
    <<~XML
      <w:p>
        <w:pPr>
          #{"<w:bidi/>" if rtl?}
          <w:jc w:val="#{rtl? ? 'right' : 'left'}"/>
          <w:spacing w:after="#{spacing_after}"/>
        </w:pPr>
        #{run(text, size: size, bold: bold, color: color)}
      </w:p>
    XML
  end

  def run(text, size: BODY_SIZE, bold: false, color: nil)
    <<~XML
      <w:r>
        <w:rPr>
          #{"<w:b/>" if bold}
          <w:sz w:val="#{size}"/>
          #{"<w:color w:val=\"#{color}\"/>" if color}
          #{"<w:rtl/>" if rtl?}
        </w:rPr>
        <w:t xml:space="preserve">#{escape(text)}</w:t>
      </w:r>
    XML
  end

  def heading(text)
    paragraph(text, size: HEADING_SIZE, bold: true, color: primary, spacing_after: 200)
  end

  def spacer
    paragraph("", spacing_after: 200)
  end

  def page_break
    %(<w:p><w:r><w:br w:type="page"/></w:r></w:p>)
  end

  def two_column_table(pairs)
    table(nil, pairs.map { |label, value| [ label.to_s, value.to_s ] })
  end

  def table(headers, rows)
    return "" if rows.blank?

    header_row = headers ? table_row(headers, header: true) : ""
    <<~XML
      <w:tbl>
        <w:tblPr>
          <w:tblStyle w:val="TableGrid"/>
          <w:tblW w:w="5000" w:type="pct"/>
          #{"<w:bidiVisual/>" if rtl?}
          <w:tblBorders>
            #{%w[top left bottom right insideH insideV].map { |edge| %(<w:#{edge} w:val="single" w:sz="4" w:color="E3E3E3"/>) }.join}
          </w:tblBorders>
        </w:tblPr>
        #{header_row}
        #{rows.map { |row| table_row(row) }.join("\n")}
      </w:tbl>
      #{spacer}
    XML
  end

  def table_row(cells, header: false)
    <<~XML
      <w:tr>
        #{cells.map { |cell| table_cell(cell, header: header) }.join("\n")}
      </w:tr>
    XML
  end

  def table_cell(text, header: false)
    <<~XML
      <w:tc>
        <w:tcPr>#{'<w:shd w:val="clear" w:fill="F7F7FD"/>' if header}</w:tcPr>
        #{paragraph(text.to_s, size: SMALL_SIZE, bold: header, spacing_after: 40)}
      </w:tc>
    XML
  end

  # bidi on the section makes the whole document right-to-left, which is what
  # puts the page numbering and table direction the right way round.
  def section_properties
    <<~XML
      <w:sectPr>
        #{"<w:bidi/>" if rtl?}
        <w:pgSz w:w="11906" w:h="16838"/>
        <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>
      </w:sectPr>
    XML
  end

  def styles
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:styles #{NAMESPACE}>
        <w:docDefaults>
          <w:rPrDefault><w:rPr><w:sz w:val="#{BODY_SIZE}"/></w:rPr></w:rPrDefault>
        </w:docDefaults>
        <w:style w:type="table" w:styleId="TableGrid">
          <w:name w:val="Table Grid"/>
        </w:style>
      </w:styles>
    XML
  end

  def content_types
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      </Types>
    XML
  end

  def package_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      </Relationships>
    XML
  end

  def document_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def translate(key, fallback = "")
    I18n.t(key, locale: locale, default: fallback)
  end

  # Text reaching here can be tagged binary even when it holds valid UTF-8 —
  # anything read as bytes rather than characters arrives that way. Encoding
  # such a string raises, which would fail the whole document over one field, so
  # the bytes are reinterpreted first and anything genuinely undecodable is
  # replaced rather than allowed to abort the render.
  def escape(text)
    string = text.to_s
    string = string.dup.force_encoding(Encoding::UTF_8) unless string.encoding == Encoding::UTF_8
    string = string.scrub("?") unless string.valid_encoding?

    string.encode(xml: :text)
  end
end
