# Keeps a procedure's steps and its diagram describing the same procedure.
#
# The steps table and the diagram were two separate objects that a user filled
# in twice. This draws the diagram from the steps — start, one task per step in
# order, end, joined by sequence flow — and afterwards carries a change on
# either side to the other. A task remembers which step it came from, so the
# link survives renaming.
#
# Only what both sides hold is synchronised: title/activity, performer/
# responsible position, and description. Durations, gateways and artifacts
# belong to one side only and are left alone.
module DiagramStepSync
  SYNC_FLAG = :diagram_step_sync_in_progress

  module_function

  def syncing?
    Thread.current[SYNC_FLAG] == true
  end

  # Runs a block with the echo guard set, so the write-back does not trigger the
  # opposite write-back.
  def quietly
    Thread.current[SYNC_FLAG] = true
    yield
  ensure
    Thread.current[SYNC_FLAG] = false
  end

  # Builds or refreshes the diagram from the owner's steps (a procedure record,
  # or a process for older diagrams). Idempotent: a linked task is updated in
  # place, a new step gets a new task, and a task whose step is gone is
  # removed. Tasks the user added by hand are kept.
  def generate(diagram, owner)
    quietly do
      diagram.transaction do
        steps = owner.steps.ordered.to_a
        start = ensure_event(diagram, "startEvent", I18n.t("architect.sync.start"))
        finish = ensure_event(diagram, "endEvent", I18n.t("architect.sync.end"))

        tasks = steps.map { |step| task_for(diagram, step) }
        remove_orphans(diagram, steps)

        renumber(diagram, [ start ] + tasks + [ finish ])
        rebuild_sequence(diagram, [ start ] + tasks + [ finish ])
      end
    end
    diagram
  end

  def step_to_element(step)
    element = step.diagram_element
    return if element.nil?

    quietly do
      element.update!(title: step.activity, performer: step.responsible_title, description: step.description,
        position: step.position)
    end
  end

  def element_to_step(element)
    step = element.pp_process_step
    return if step.nil?

    quietly do
      step.update!(activity: element.title, responsible_title: element.performer, description: element.description)
    end
  end

  # --- helpers --------------------------------------------------------------

  def ensure_event(diagram, type, title)
    diagram.elements.find_by(element_type: type) ||
      diagram.elements.create!(element_type: type, title: title, position: 0)
  end

  def task_for(diagram, step)
    element = diagram.elements.find_by(pp_process_step_id: step.id)
    attributes = { title: step.activity, performer: step.responsible_title, description: step.description }

    if element
      element.update!(attributes)
      element
    else
      diagram.elements.create!(attributes.merge(element_type: "userTask", pp_process_step: step, position: step.position))
    end
  end

  def remove_orphans(diagram, steps)
    diagram.elements.where.not(pp_process_step_id: nil)
      .where.not(pp_process_step_id: steps.map(&:id)).destroy_all
  end

  def renumber(diagram, ordered)
    ordered.each_with_index { |element, index| element.update_column(:position, index) }
    # Hand-added elements keep their relative order after the generated ones.
    diagram.elements.where.not(id: ordered.map(&:id)).order(:position).each_with_index do |element, index|
      element.update_column(:position, ordered.size + index)
    end
  end

  # The generated chain is start -> steps -> end. Existing flows among the
  # generated elements are replaced; flows touching hand-added elements stay.
  def rebuild_sequence(diagram, ordered)
    ids = ordered.map(&:id)
    diagram.flows.where(from_element_id: ids, to_element_id: ids, kind: "sequence").destroy_all

    ordered.each_cons(2) do |from, to|
      diagram.flows.create!(from_element: from, to_element: to, kind: "sequence")
    end
  end
end
