require "test_helper"

# R09 — an upload started inside a folder was filed at the library root because
# the dialog's folder select arrived blank.
class UploadsFolderContextTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Ctx Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "ctx-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Ctx Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @folder = Folder.create!(company: @company, name: "Evidence", created_by: @admin.id)
  end

  def upload_file
    Rack::Test::UploadedFile.new(StringIO.new("evidence bytes"), "text/plain", original_filename: "qa.txt")
  end

  test "an upload started inside a folder is filed there even when the select is blank" do
    sign_in @admin
    post uploads_path, params: {
      context_folder_id: @folder.id,
      upload: { name: "Folder evidence", folder_id: "", file: upload_file, visibility: "public" }
    }

    upload = Upload.order(:created_at).last
    assert_equal "Folder evidence", upload.name
    assert_equal @folder.id, upload.folder_id
  end

  test "a folder chosen explicitly wins over the context" do
    other = Folder.create!(company: @company, name: "Other", created_by: @admin.id)

    sign_in @admin
    post uploads_path, params: {
      context_folder_id: @folder.id,
      upload: { name: "Chosen", folder_id: other.id, file: upload_file, visibility: "public" }
    }

    assert_equal other.id, Upload.order(:created_at).last.folder_id
  end

  test "the dialog inside a folder carries that folder as context" do
    sign_in @admin
    get folder_path(@folder)

    assert_select "input[name=?][value=?]", "context_folder_id", @folder.id
  end
end
