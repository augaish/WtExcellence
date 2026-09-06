require "test_helper"

class PpRecordDocumentServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Doc Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @user = User.create!(email: "doc-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Owner", is_active: true)
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy")
  end

  def uploaded_file(name = "policy.pdf")
    file = Tempfile.new([ "doc", ".pdf" ])
    file.write("%PDF-1.4 test")
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: name, type: "application/pdf")
  end

  test "files an upload into the Library under P&P > type" do
    upload = PpRecordDocumentService.upload_into_library(
      file: uploaded_file, record: @record, company: @company, user: @user
    )

    assert upload.persisted?
    assert_equal @company.id, upload.company_id
    assert upload.file.attached?

    type_folder = upload.folder
    assert_equal "Policy", type_folder.name
    assert_equal PpRecordDocumentService::ROOT_FOLDER_NAME, type_folder.parent.name
    assert_nil type_folder.parent.parent_id
  end

  test "reuses the same folders across uploads" do
    2.times { PpRecordDocumentService.upload_into_library(file: uploaded_file, record: @record, company: @company, user: @user) }

    assert_equal 1, @company.folders.where(name: PpRecordDocumentService::ROOT_FOLDER_NAME).count
    assert_equal 1, @company.folders.where(name: "Policy").count
  end

  test "different record types get their own sub-folder" do
    form_record = @company.pp_records.create!(record_type: "form", title_en: "Request Form")

    PpRecordDocumentService.upload_into_library(file: uploaded_file, record: @record, company: @company, user: @user)
    PpRecordDocumentService.upload_into_library(file: uploaded_file, record: form_record, company: @company, user: @user)

    root = @company.folders.find_by(name: PpRecordDocumentService::ROOT_FOLDER_NAME)
    assert_equal %w[Form Policy], @company.folders.where(parent_id: root.id).pluck(:name).sort
  end

  test "returns nil without a file" do
    assert_nil PpRecordDocumentService.upload_into_library(
      file: nil, record: @record, company: @company, user: @user
    )
  end

  test "folders are scoped to the company" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    PpRecordDocumentService.upload_into_library(file: uploaded_file, record: @record, company: @company, user: @user)

    assert_equal 0, other.folders.count
  end
end
