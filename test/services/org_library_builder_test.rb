require "test_helper"

class OrgLibraryBuilderTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Lib Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @group = @company.org_groups.create!(name_en: "Support", color: "#0B4F6C")
    @root = @company.org_units.create!(name_en: "Minister", level: 1)
    @hr = @company.org_units.create!(name_en: "Human Resources", level: 2, parent: @root, org_group: @group)
    @payroll = @company.org_units.create!(name_en: "Payroll", level: 3, parent: @hr)
  end

  test "builds one folder per unit, nested like the structure and coloured by group" do
    result = OrgLibraryBuilder.build(@company, user: nil)

    assert_equal 3, result.created
    assert_equal 0, result.updated

    hr_folder = Folder.find_by(org_unit_id: @hr.id)
    assert_equal "Human Resources", hr_folder.name
    assert_equal "#0B4F6C", hr_folder.color
    assert_equal Folder.find_by(org_unit_id: @root.id), hr_folder.parent
    assert_equal hr_folder, Folder.find_by(org_unit_id: @payroll.id).parent
    assert_equal @company.id, hr_folder.company_id
  end

  test "a rebuild follows renames and moves without creating duplicates" do
    OrgLibraryBuilder.build(@company, user: nil)
    @payroll.update!(name_en: "Payroll & Benefits", parent: @root, level: 2)

    result = OrgLibraryBuilder.build(@company, user: nil)

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal 3, Folder.where(company_id: @company.id).count
    folder = Folder.find_by(org_unit_id: @payroll.id)
    assert_equal "Payroll & Benefits", folder.name
    assert_equal Folder.find_by(org_unit_id: @root.id), folder.parent
  end

  test "a rebuild never deletes a folder whose unit is gone" do
    OrgLibraryBuilder.build(@company, user: nil)
    @payroll.update!(active: false)

    OrgLibraryBuilder.build(@company, user: nil)

    assert Folder.exists?(org_unit_id: @payroll.id)
  end

  test "uses the Arabic name when built from an Arabic session" do
    @hr.update!(name_ar: "الموارد البشرية")
    OrgLibraryBuilder.build(@company, user: nil, locale: :ar)

    assert_equal "الموارد البشرية", Folder.find_by(org_unit_id: @hr.id).name
  end
end
