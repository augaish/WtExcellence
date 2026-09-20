require "test_helper"

# Test team items 11 and 16.
class Group7DiagramLibraryTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "G7 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = User.create!(email: "g7-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  test "11: the picture separates the external pool, marks task types, routes arrows in channels and backward arrows below" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Any", description: "x")
    diagram = @company.pp_diagrams.create!(owner: record, name: "Shapes")
    start = diagram.elements.create!(element_type: "startEvent", title: "Start", position: 0)
    a = diagram.elements.create!(element_type: "userTask", title: "Review", performer: "HR", position: 1)
    b = diagram.elements.create!(element_type: "serviceTask", title: "Notify", performer: "System", position: 2)
    ext = diagram.elements.create!(element_type: "receiveTask", title: "Reply", performer: "Customer", scope: "external", position: 3)
    diagram.flows.create!(from_element: start, to_element: a)
    diagram.flows.create!(from_element: a, to_element: b)
    diagram.flows.create!(from_element: b, to_element: a)
    diagram.flows.create!(from_element: b, to_element: ext, kind: "message")

    get dashboard_pp_diagram_path(diagram)
    svg = response.body
    assert_match(/stroke="#5C3984" stroke-width="1\.5"\/>/, svg, "the external pool has its own border")
    renderer = ProcessDiagramRenderer.new(diagram)
    renderer.render
    assert_equal 4, renderer.layout.values.map { |p| p[:lane] }.uniq.size, "start lane, HR, System and the external pool"
    assert_includes svg, "aria-hidden=\"true\"><circle", "a user task carries the person glyph"
    forward = svg.scan(/d="M \d+ \d+ H \d+ V \d+ H \d+"/)
    assert forward.size >= 2, "forward arrows are elbows"
    assert_match(/d="M \d+ \d+ H \d+ V \d+ H \d+ V \d+ H \d+"/, svg, "the backward arrow dips below the lane")

    assert_select "[data-element-fields-target=field][data-show-for=gateway]"
    assert_select "[data-element-fields-target=field][data-show-for=task]", 2
  end

  test "16: the Library browses unit folders by organisational level and group" do
    ministry = @company.org_units.create!(name_en: "Ministry", level: 1)
    deputy = @company.org_units.create!(name_en: "Deputyship", level: 2, parent: ministry)
    dept = @company.org_units.create!(name_en: "Department", level: 3, parent: deputy)
    OrgLibraryBuilder.new(@company, user: @admin).build

    get library_path
    assert_response :success
    assert_select "select[name=level]"
    assert_includes response.body, "Ministry"

    get library_path(level: 3)
    dept_folder = Folder.find_by(org_unit_id: dept.id)
    listed = css_select("[data-folder-id]").map { |n| n["data-folder-id"] }.uniq
    assert_equal [ dept_folder.id ], listed, "only the level-3 unit's folder is listed"
    get library_path(level: 2)
    listed = css_select("[data-folder-id]").map { |n| n["data-folder-id"] }.uniq
    assert_equal [ Folder.find_by(org_unit_id: deputy.id).id ], listed
  end
end
