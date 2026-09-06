require "test_helper"

class Dashboard::PpDiagramsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "DiaCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("dia-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("dia-viewer", CompanyUser::ROLES[:company_viewer])

    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Onboarding", code: "PRO-01")
    @process = @company.pp_processes.create!(name_en: "Hiring", level: 1, code: "P-01")
    @diagram = @company.pp_diagrams.create!(owner: @record, name: "Onboarding process")
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "the editor renders the generated diagram" do
    sign_in @admin
    @diagram.elements.create!(element_type: "startEvent", title: "Start", performer: "HR")

    get dashboard_pp_diagram_path(@diagram)

    assert_response :success
    assert_select "svg"
    assert_select "body", text: /Start/
  end

  test "it is a structured editor, not a drawing canvas" do
    sign_in @admin
    get dashboard_pp_diagram_path(@diagram)

    assert_response :success
    # Elements are added through a form with typed fields.
    assert_select "select[name='pp_diagram_element[element_type]']"
    assert_select "input[name='pp_diagram_element[title]']"
    assert_select "input[name='pp_diagram_element[performer]']"
    assert_select "textarea[name='pp_diagram_element[description]']"
    assert_select "input[name='pp_diagram_element[input]']"
    assert_select "input[name='pp_diagram_element[output]']"
  end

  test "a diagram is created from a record" do
    sign_in @admin

    assert_difference -> { @company.pp_diagrams.count }, 1 do
      post dashboard_pp_diagrams_path, params: {
        owner_type: "PpRecord", owner_id: @record.id,
        pp_diagram: { name: "New flow", trigger_text: "Request received" }
      }
    end

    diagram = @company.pp_diagrams.order(:created_at).last
    assert_equal @record, diagram.owner
    assert_equal "Request received", diagram.trigger_text
  end

  test "a diagram can also be created from a process" do
    sign_in @admin

    post dashboard_pp_diagrams_path, params: {
      owner_type: "PpProcess", owner_id: @process.id, pp_diagram: { name: "Hiring flow" }
    }

    assert_equal @process, @company.pp_diagrams.order(:created_at).last.owner
  end

  test "elements are added one at a time and keep their order" do
    sign_in @admin

    post add_element_dashboard_pp_diagram_path(@diagram), params: {
      pp_diagram_element: { element_type: "startEvent", title: "Start", performer: "HR" }
    }
    post add_element_dashboard_pp_diagram_path(@diagram), params: {
      pp_diagram_element: { element_type: "userTask", title: "Review", performer: "HR",
                            description: "Check it", input: "Draft", output: "Reviewed" }
    }

    elements = @diagram.reload.elements.to_a
    assert_equal %w[Start Review], elements.map(&:title)
    assert_equal [ 0, 1 ], elements.map(&:position)
    assert_equal "Draft", elements.last.input
  end

  test "an element can be removed" do
    sign_in @admin
    element = @diagram.elements.create!(element_type: "manualTask", title: "Step")

    assert_difference -> { @diagram.elements.count }, -1 do
      delete destroy_element_dashboard_pp_diagram_path(@diagram, element_id: element.id)
    end
  end

  test "flows connect two elements" do
    sign_in @admin
    a = @diagram.elements.create!(element_type: "startEvent", title: "Start", performer: "HR")
    b = @diagram.elements.create!(element_type: "userTask", title: "Review", performer: "HR")

    assert_difference -> { @diagram.flows.count }, 1 do
      post add_flow_dashboard_pp_diagram_path(@diagram), params: {
        from_element_id: a.id, to_element_id: b.id, kind: "sequence", label: "always"
      }
    end

    assert_equal "sequence", @diagram.flows.first.kind
  end

  test "a self-referencing flow is refused" do
    sign_in @admin
    a = @diagram.elements.create!(element_type: "manualTask", title: "Step")

    assert_no_difference -> { @diagram.flows.count } do
      post add_flow_dashboard_pp_diagram_path(@diagram), params: {
        from_element_id: a.id, to_element_id: a.id, kind: "sequence"
      }
    end
  end

  test "a cross-participant sequence flow is saved but flagged in the UI" do
    sign_in @admin
    inside = @diagram.elements.create!(element_type: "userTask", title: "Send", performer: "HR")
    outside = @diagram.elements.create!(element_type: "receiveTask", title: "Receive",
      performer: "Supplier", scope: "external")
    @diagram.flows.create!(from_element: inside, to_element: outside, kind: "sequence")

    get dashboard_pp_diagram_path(@diagram)

    assert_response :success
    assert_includes response.body, I18n.t("architect.invalid_cross_pool")
  end

  test "a viewer can read a diagram but not change it" do
    sign_in @viewer
    get dashboard_pp_diagram_path(@diagram)
    assert_response :success
    assert_select "select[name='pp_diagram_element[element_type]']", count: 0

    assert_no_difference -> { @diagram.elements.count } do
      post add_element_dashboard_pp_diagram_path(@diagram), params: {
        pp_diagram_element: { element_type: "manualTask", title: "Sneaky" }
      }
    end
  end

  test "another company's diagram is not reachable" do
    sign_in @admin
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign_record = other.pp_records.create!(record_type: "policy", title_en: "Foreign")
    foreign = other.pp_diagrams.create!(owner: foreign_record, name: "Foreign")

    get dashboard_pp_diagram_path(foreign)

    assert_redirected_to dashboard_pp_records_path
  end

  test "the record card links to the Process Architect and lists diagrams" do
    sign_in @admin
    get dashboard_pp_record_path(@record)

    assert_response :success
    assert_select "a[href=?]", new_dashboard_pp_diagram_path(owner_type: "PpRecord", owner_id: @record.id)
    assert_select "a[href=?]", dashboard_pp_diagram_path(@diagram)
  end

  test "the new and edit forms render" do
    sign_in @admin

    get new_dashboard_pp_diagram_path(owner_type: "PpRecord", owner_id: @record.id)
    assert_response :success

    get edit_dashboard_pp_diagram_path(@diagram)
    assert_response :success
  end

  test "deleting a diagram returns to its owner" do
    sign_in @admin

    assert_difference -> { @company.pp_diagrams.count }, -1 do
      delete dashboard_pp_diagram_path(@diagram)
    end
    assert_redirected_to dashboard_pp_record_path(@record)
  end
end
