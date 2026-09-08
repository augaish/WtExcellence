require "test_helper"
require "rexml/document"

# A .docx is a zip of XML parts. These tests open the produced file the way Word
# would, rather than trusting that bytes were written.
class RecordDocxRendererTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Docx Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @unit = @company.org_units.create!(name_en: "Institutional Excellence", name_ar: "التميز المؤسسي", level: 1)
    @process = @company.pp_processes.create!(name_en: "Policy development", level: 1,
      objective: "Govern how policies are written")
    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Policy Development Procedure",
      title_ar: "إجراء تطوير السياسات", code: "PRO-01", pp_process: @process,
      owner_org_unit: @unit, version_label: "v1.0", classification: "secret")
    @process.steps.create!(position: 1, activity: "Draft the policy", responsible_title: "Policies Specialist",
      duration_value: 3, duration_unit: "days")
  end

  def render(locale: :en)
    RecordDocxRenderer.new(RecordDocument.new(@record.reload, locale: locale)).render
  end

  def archive(bytes)
    Zip::File.open_buffer(StringIO.new(bytes))
  end

  def part(bytes, name)
    # Zip returns binary; the parts are UTF-8 XML and are compared as such.
    archive(bytes).get_entry(name).get_input_stream.read.force_encoding(Encoding::UTF_8)
  end

  def entries(bytes)
    archive(bytes).entries.map(&:name)
  end

  test "the file contains the parts Word requires" do
    names = entries(render)

    %w[[Content_Types].xml _rels/.rels word/document.xml word/styles.xml
       word/_rels/document.xml.rels].each do |required|
      assert_includes names, required, "#{required} is missing, so Word would refuse the file"
    end
  end

  test "every part is well-formed XML" do
    bytes = render

    entries(bytes).each do |name|
      next unless name.end_with?(".xml") || name.end_with?(".rels")

      assert_nothing_raised { REXML::Document.new(part(bytes, name)) }
    end
  end

  test "the document carries its own content" do
    body = part(render, "word/document.xml")

    assert_includes body, "Policy Development Procedure"
    assert_includes body, "PRO-01"
    assert_includes body, "Draft the policy"
    assert_includes body, DocumentClassification.label("secret")
  end

  test "Arabic is marked right to left at every level Word looks at" do
    body = part(render(locale: :ar), "word/document.xml")

    assert_includes body, "<w:bidi/>", "the paragraphs are not marked bidi"
    assert_includes body, "<w:rtl/>", "the runs are not marked rtl"
    assert_includes body, "<w:bidiVisual/>", "table columns would run the wrong way"
    assert_includes body, 'w:val="right"'
    assert_includes body, "إجراء تطوير السياسات"
  end

  test "English is not marked right to left" do
    body = part(render(locale: :en), "word/document.xml")

    assert_not_includes body, "<w:bidi/>"
    assert_not_includes body, "<w:rtl/>"
  end

  test "text that looks like markup cannot break the file" do
    @record.update!(title_en: "Procedure <w:p> & \"quoted\"")
    body = part(render, "word/document.xml")

    assert_nothing_raised { REXML::Document.new(body) }
    assert_includes body, "&lt;w:p&gt;"
  end

  test "text tagged as binary does not fail the whole document" do
    # Values read as bytes rather than characters arrive tagged ASCII-8BIT even
    # when they hold valid UTF-8; encoding one of those raises.
    @record.update!(title_ar: "سياسة حوكمة البيانات".dup.force_encoding(Encoding::ASCII_8BIT))

    body = nil
    assert_nothing_raised { body = part(render(locale: :ar), "word/document.xml") }
    assert_includes body, "سياسة حوكمة البيانات"
  end

  test "undecodable bytes are replaced rather than aborting the render" do
    @record.title_en = "Broken \xFF title".dup.force_encoding(Encoding::ASCII_8BIT)

    assert_nothing_raised { RecordDocxRenderer.new(RecordDocument.new(@record)).render }
  end

  test "the filename identifies the document and is safe on disk" do
    name = RecordDocxRenderer.new(RecordDocument.new(@record)).filename

    assert_equal "PRO-01 - Policy Development Procedure.docx", name
  end

  test "a record with almost nothing in it still produces a valid file" do
    bare = @company.pp_records.create!(record_type: "policy", title_en: "Bare")
    bytes = RecordDocxRenderer.new(RecordDocument.new(bare)).render

    assert_nothing_raised { REXML::Document.new(part(bytes, "word/document.xml")) }
    assert_includes part(bytes, "word/document.xml"), "Bare"
  end

  test "the Word version says the diagram is only in the browser" do
    @company.pp_diagrams.create!(owner: @process, name: "Flow")

    body = part(render, "word/document.xml")
    assert_includes body, I18n.t("record_document.diagram_omitted")
  end
end
