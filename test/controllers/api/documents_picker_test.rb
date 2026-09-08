require "test_helper"

# F08 — the CAPA document picker rendered blank with no empty state and no
# error, so there was no way to tell whether the cause was file type, filtering,
# permissions, or a failed response.
class Api::DocumentsPickerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Pick Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "pick-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Pick Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @folder = Folder.create!(company: @company, name: "Evidence", created_by: @admin.id)
  end

  def upload_file(name:, filename:, content_type:)
    upload = Upload.new(company: @company, folder: @folder, name: name, uploaded_by: @admin.id,
      visibility: "public", filename: filename, mime_type: content_type, size_bytes: 11)
    upload.file.attach(io: StringIO.new("some bytes"), filename: filename, content_type: content_type)
    upload.save!
    upload
  end

  def documents_from(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed["documents"] : parsed
  end

  test "the picker returns documents of every common type" do
    text = upload_file(name: "Notes", filename: "notes.txt", content_type: "text/plain")
    pdf = upload_file(name: "Report", filename: "report.pdf", content_type: "application/pdf")
    docx = upload_file(name: "Policy", filename: "policy.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

    sign_in @admin
    get "/api/documents"

    assert_response :success
    ids = documents_from(response.body).map { |d| d["id"] }
    [ text, pdf, docx ].each do |upload|
      assert_includes ids, upload.id, "#{upload.filename} was not offered by the picker"
    end
  end

  test "filtering by folder returns that folder's documents" do
    inside = upload_file(name: "Inside", filename: "inside.pdf", content_type: "application/pdf")

    sign_in @admin
    get "/api/documents", params: { folder_id: @folder.id }

    assert_response :success
    assert_equal [ inside.id ], documents_from(response.body).map { |d| d["id"] }
  end

  test "another company's documents are never offered" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = Upload.new(company: other, name: "Foreign", uploaded_by: @admin.id, visibility: "public",
      filename: "foreign.pdf", mime_type: "application/pdf", size_bytes: 5)
    foreign.file.attach(io: StringIO.new("x"), filename: "foreign.pdf", content_type: "application/pdf")
    foreign.save!

    sign_in @admin
    get "/api/documents"

    assert_response :success
    assert_not_includes documents_from(response.body).map { |d| d["id"] }, foreign.id
  end
end
