# The maths behind the P&P dashboard widgets. Pure computation over records and
# their transition history — no rendering, so it is cheap to test and the charts
# stay presentation-only.
class PpMonitoringService
  # Work-status states, in the precedence order the spec fixes:
  #   notStarted -> late -> onTrack, plus completedLate for finished work whose
  #   history shows a stage that overran its target at the time.
  STATUSES = %w[not_started late on_track completed_late completed].freeze

  def self.for(company)
    new(company)
  end

  def initialize(company)
    @company = company
    @working_days = WorkingDaysService.new(company)
  end

  def records
    @records ||= @company.pp_records.active.to_a
  end

  # --- Calculation 1: lifecycle funnel ------------------------------------
  #
  # "reached" counts every record at or PAST a phase's first stage — not just
  # those sitting in it — so the funnel shows how far work has progressed
  # overall rather than a snapshot of current occupancy.
  def funnel(now = Time.current)
    total = target_total

    PpStage::PHASES.map do |phase|
      first_stage = PpStage.in_phase(phase).first[:key]
      threshold = PpStage.index(first_stage)

      reached = records.count do |record|
        position = PpStage.index(record.stage_key)
        position.present? && position >= threshold
      end

      {
        phase: phase,
        label: PpStage.phase_label(phase),
        reached: reached,
        total: total,
        pct: total.positive? ? (reached.to_f / total * 100).round(1) : 0.0
      }
    end
  end

  # The configured yearly target, or the record count when none is set.
  def target_total
    configured = @company.pp_yearly_target.to_i
    configured.positive? ? configured : records.size
  end

  # --- Calculation 2: per-record work status ------------------------------
  def status_for(record, now = Time.current)
    if record.completed?
      return completed_late?(record) ? "completed_late" : "completed"
    end

    return "not_started" if untouched?(record)
    return "late" if record.stage_late?(now)

    "on_track"
  end

  def status_breakdown(now = Time.current)
    counts = STATUSES.index_with { 0 }
    records.each { |record| counts[status_for(record, now)] += 1 }
    counts
  end

  # Still at the very first stage and never moved.
  def untouched?(record)
    record.stage_key == PpStage.first_key_for(record.record_type) && record.stage_transitions.none?
  end

  # Finished, but at least one stage it has since moved past ran longer than
  # that stage's target at the time. This needs the full transition history,
  # which the Documenter has recorded since Phase 3.
  def completed_late?(record)
    transitions = record.stage_transitions.chronological.to_a
    return false if transitions.empty?

    entered_at = record.created_at
    current = PpStage.first_key_for(record.record_type)

    transitions.any? do |transition|
      stage = transition.from_stage.presence || current
      target = PpStageTarget.days_for(@company, stage)
      overran = target.positive? && @working_days.between(entered_at, transition.created_at) > target

      entered_at = transition.created_at
      current = transition.to_stage
      overran
    end
  end

  # --- Calculation 3: roll-up by org unit ---------------------------------
  #
  # A node with no records of its own takes its numbers entirely from its
  # children, and every direct child counts EQUALLY regardless of how many
  # records it holds. A node is not_started only when every descendant is.
  def rollup
    units = @company.org_units.active.ordered.to_a
    by_parent = units.group_by(&:parent_id)
    records_by_unit = records.group_by(&:owner_org_unit_id)

    (by_parent[nil] || []).map { |root| rollup_node(root, by_parent, records_by_unit) }
  end

  private

  def rollup_node(unit, by_parent, records_by_unit)
    children = (by_parent[unit.id] || []).map { |child| rollup_node(child, by_parent, records_by_unit) }
    own_records = records_by_unit[unit.id] || []

    own_completion =
      if own_records.any?
        completed = own_records.count { |r| r.completed? }
        (completed.to_f / own_records.size * 100)
      end

    child_completions = children.map { |c| c[:completion_pct] }.compact

    completion =
      if own_completion && child_completions.any?
        # Own records count as one more equally-weighted contributor.
        ((own_completion + child_completions.sum) / (child_completions.size + 1))
      elsif own_completion
        own_completion
      elsif child_completions.any?
        # Equal weight per child, NOT weighted by record count.
        child_completions.sum / child_completions.size
      end

    own_started = own_records.any? { |r| !untouched?(r) }
    started = own_started || children.any? { |c| c[:started] }

    {
      id: unit.id,
      name: unit.display_name,
      level: unit.level,
      colour: unit.org_group&.color,
      own_records: own_records.size,
      total_records: own_records.size + children.sum { |c| c[:total_records] },
      completion_pct: completion&.round(1),
      started: started,
      not_started: !started,
      children: children
    }
  end
end
