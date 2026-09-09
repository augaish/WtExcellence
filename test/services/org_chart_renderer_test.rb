require "test_helper"

class OrgChartRendererTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Chart Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @group = @company.org_groups.create!(name_en: "Support", color: "#0B4F6C")

    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy Minister", level: 2, parent: @minister)
    @finance = @company.org_units.create!(name_en: "Finance", level: 3, parent: @deputy, org_group: @group)
    @hr = @company.org_units.create!(name_en: "Human Resources", level: 3, parent: @deputy)
  end

  def svg(units = @company.org_units.order(:level))
    OrgChartRenderer.render(units)
  end

  test "an empty structure renders without failing" do
    assert_includes OrgChartRenderer.render([]), "<svg"
  end

  test "every unit gets a clickable box carrying its id" do
    output = svg

    [ @minister, @deputy, @finance, @hr ].each do |unit|
      assert_includes output, %(data-org-chart-unit-id-param="#{unit.id}")
      assert_includes output, unit.name_en
    end
    assert_equal 4, output.scan('class="org-chart-node"').size
  end

  test "a unit is coloured by its group, and falls back to the house colour" do
    output = svg

    assert_includes output, "#0B4F6C"
    assert_includes output, OrgChartRenderer::PRIMARY
  end

  test "every child is joined to its parent by a reporting line" do
    output = svg

    # Three children, so three connectors; the root has none.
    assert_equal 3, output.scan("<path").size
  end

  test "a parent sits above its children" do
    OrgChartRenderer.render(@company.org_units.order(:level))
    renderer = OrgChartRenderer.new(@company.org_units.order(:level).to_a)
    renderer.render
    positions = renderer.instance_variable_get(:@positions)

    assert_operator positions[@minister.id][:y], :<, positions[@deputy.id][:y]
    assert_operator positions[@deputy.id][:y], :<, positions[@finance.id][:y]
    assert_equal positions[@finance.id][:y], positions[@hr.id][:y], "siblings share a row"
  end

  test "a filtered subtree still renders rather than coming out blank" do
    output = OrgChartRenderer.render([ @finance, @hr ])

    assert_includes output, @finance.name_en
    assert_includes output, @hr.name_en
    assert_equal 0, output.scan("<path").size, "their parent is not in the set, so there is nothing to join to"
  end

  test "unit names are escaped rather than injected into the drawing" do
    hostile = @company.org_units.create!(name_en: "<script>alert(1)</script>", level: 1)
    output = OrgChartRenderer.render([ hostile ])

    assert_not_includes output, "<script>"
    assert_includes output, "&lt;script&gt;"
  end

  test "Arabic labels are anchored to the right edge so they stay inside the box" do
    unit = @company.org_units.create!(name_en: "Legal", name_ar: "الإدارة القانونية", level: 1)
    output = OrgChartRenderer.render([ unit ], locale: :ar)

    assert_includes output, 'direction="rtl"'
    assert_includes output, 'text-anchor="end"'
    assert_includes output, "الإدارة القانونية"
    # The anchor point is the inner right edge, not the left one.
    assert_includes output, %(x="#{OrgChartRenderer::PADDING + OrgChartRenderer::BOX_WIDTH - OrgChartRenderer::TEXT_INSET}")
  end

  test "English labels stay anchored to the left" do
    output = svg
    assert_includes output, 'direction="ltr"'
    assert_includes output, 'text-anchor="start"'
  end

  test "a long name wraps onto a second line instead of running out of the box" do
    unit = @company.org_units.create!(name_en: "General Directorate of Institutional Excellence", level: 1)
    output = OrgChartRenderer.render([ unit ])

    assert_includes output, ">General Directorate of<"
    assert_includes output, ">Institutional Excellence<"
  end
end
