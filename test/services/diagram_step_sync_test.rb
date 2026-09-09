require "test_helper"

# The steps table and the diagram were two objects filled in twice.
class DiagramStepSyncTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Sync Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @process = @company.pp_processes.create!(name_en: "Purchase orders", level: 1, category: "core")
    @s1 = @process.steps.create!(position: 1, activity: "Validate request", responsible_title: "Procurement Officer")
    @s2 = @process.steps.create!(position: 2, activity: "Verify budget", responsible_title: "Finance Officer")
    @s3 = @process.steps.create!(position: 3, activity: "Issue order", responsible_title: "Procurement Head")
    @diagram = @company.pp_diagrams.create!(owner: @process, name: "PO flow")
  end

  test "the diagram is drawn from the steps: start, one task per step in order, end" do
    DiagramStepSync.generate(@diagram, @process)
    elements = @diagram.elements.order(:position).to_a

    assert_equal %w[startEvent userTask userTask userTask endEvent], elements.map(&:element_type)
    assert_equal [ "Validate request", "Verify budget", "Issue order" ], elements.select(&:task?).map(&:title)
    assert_equal [ "Procurement Officer", "Finance Officer", "Procurement Head" ], elements.select(&:task?).map(&:performer)
    assert_equal 4, @diagram.flows.count, "start->s1->s2->s3->end"
    assert @diagram.flows.all? { |f| f.kind == "sequence" }
  end

  test "drawing again after a change updates in place rather than duplicating" do
    DiagramStepSync.generate(@diagram, @process)
    @s2.update!(activity: "Verify budget and cost centre")
    @process.steps.create!(position: 4, activity: "Retain evidence", responsible_title: "Procurement Officer")

    DiagramStepSync.generate(@diagram.reload, @process.reload)
    tasks = @diagram.elements.where(element_type: "userTask").order(:position)

    assert_equal 4, tasks.count
    assert_equal "Verify budget and cost centre", tasks.second.title
    assert_equal 5, @diagram.flows.count
  end

  test "a deleted step leaves the picture" do
    DiagramStepSync.generate(@diagram, @process)
    @s2.destroy

    assert_equal 2, @diagram.reload.elements.where(element_type: "userTask").count
  end

  test "editing a step reaches its task without being asked" do
    DiagramStepSync.generate(@diagram, @process)
    @s1.reload.update!(activity: "Validate the request", responsible_title: "Buyer")

    element = @diagram.elements.find_by(pp_process_step_id: @s1.id)
    assert_equal "Validate the request", element.title
    assert_equal "Buyer", element.performer
  end

  test "editing a linked task writes back to its step" do
    DiagramStepSync.generate(@diagram, @process)
    element = @diagram.elements.find_by(pp_process_step_id: @s3.id)
    element.update!(title: "Issue the purchase order", performer: "Head of Procurement")

    @s3.reload
    assert_equal "Issue the purchase order", @s3.activity
    assert_equal "Head of Procurement", @s3.responsible_title
  end

  test "the two sides do not update each other forever" do
    DiagramStepSync.generate(@diagram, @process)
    assert_nothing_raised { @s1.reload.update!(activity: "Loop check") }
    assert_equal "Loop check", @diagram.elements.find_by(pp_process_step_id: @s1.id).title
  end

  test "hand-drawn elements survive a redraw" do
    DiagramStepSync.generate(@diagram, @process)
    gateway = @diagram.elements.create!(element_type: "gateway", title: "Within budget?")

    DiagramStepSync.generate(@diagram.reload, @process)
    assert PpDiagramElement.exists?(gateway.id)
  end

  test "durations belong to the step alone and are not touched by the diagram" do
    @s1.update!(duration_value: 2, duration_unit: "hours")
    DiagramStepSync.generate(@diagram, @process)
    @diagram.elements.find_by(pp_process_step_id: @s1.id).update!(title: "Renamed")

    assert_equal 2, @s1.reload.duration_value
  end
end
