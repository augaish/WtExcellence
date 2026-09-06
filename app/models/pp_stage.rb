# The document lifecycle, exactly as the product owner specified it.
#
# This is CONFIGURATION, not a table: the sequence is fixed, so it lives in code
# where it can be reasoned about and tested. What varies per company (target
# days) lives in pp_stage_targets.
#
# Two branches make the sequence a graph rather than a straight line:
#   * s2_confirmation -> s2_stakeholders when the record has intersections with
#     other org units, otherwise straight to s2_final.
#   * s2_final -> s3_design for Procedures (they get a designed diagram),
#     otherwise straight to s4_initial.
#
# No date is ever typed. Every timestamp is stamped by the system when the
# action happens (a transition, or marking an approval received), so durations
# cannot drift from reality.
class PpStage
  PHASES = %w[inventory preparation documentation approval publishing].freeze

  # kind:
  #   :plain     - move forward, nothing captured
  #   :branch    - captures the intersections answer, which picks the next stage
  #   :approval  - holds a chain of org-unit approvals; duration is measured to
  #                the LAST approval received
  DEFINITIONS = [
    { key: "s1_verify",       phase: "inventory",     kind: :plain },
    { key: "s1_approved",     phase: "inventory",     kind: :plain },

    { key: "s2_prep",         phase: "preparation",   kind: :plain },
    { key: "s2_draftReview",  phase: "preparation",   kind: :plain },
    { key: "s2_ownerReview",  phase: "preparation",   kind: :plain },
    { key: "s2_comments",     phase: "preparation",   kind: :plain },
    { key: "s2_confirmation", phase: "preparation",   kind: :branch },
    { key: "s2_stakeholders", phase: "preparation",   kind: :approval },
    { key: "s2_final",        phase: "preparation",   kind: :plain },

    { key: "s3_design",       phase: "documentation", kind: :plain },
    { key: "s3_designReview", phase: "documentation", kind: :plain },

    { key: "s4_initial",      phase: "approval",      kind: :plain },
    { key: "s4_ownerapprove", phase: "approval",      kind: :plain },
    { key: "s4_final",        phase: "approval",      kind: :approval },

    { key: "s5_toPublish",    phase: "publishing",    kind: :plain },
    { key: "s5_published",    phase: "publishing",    kind: :plain },
    { key: "s5_closed",       phase: "publishing",    kind: :plain }
  ].freeze

  KEYS = DEFINITIONS.map { |d| d[:key] }.freeze
  FIRST_KEY = KEYS.first
  TERMINAL_KEY = "s5_closed".freeze

  # Types that go through the procedure-design phase.
  DESIGN_TYPES = %w[procedure].freeze

  # Sensible starting targets (working days), overridable per company.
  DEFAULT_TARGET_DAYS = {
    "s1_verify" => 3, "s1_approved" => 3,
    "s2_prep" => 10, "s2_draftReview" => 5, "s2_ownerReview" => 5,
    "s2_comments" => 5, "s2_confirmation" => 3, "s2_stakeholders" => 10, "s2_final" => 5,
    "s3_design" => 10, "s3_designReview" => 5,
    "s4_initial" => 5, "s4_ownerapprove" => 5, "s4_final" => 10,
    "s5_toPublish" => 3, "s5_published" => 3, "s5_closed" => 0
  }.freeze

  class << self
    def all
      DEFINITIONS
    end

    def find(key)
      DEFINITIONS.detect { |d| d[:key] == key.to_s }
    end

    def exists?(key)
      KEYS.include?(key.to_s)
    end

    def index(key)
      KEYS.index(key.to_s)
    end

    def phase_of(key)
      find(key)&.fetch(:phase, nil)
    end

    def kind_of(key)
      find(key)&.fetch(:kind, nil)
    end

    def approval_stage?(key)
      kind_of(key) == :approval
    end

    def branch_stage?(key)
      kind_of(key) == :branch
    end

    def terminal?(key)
      key.to_s == TERMINAL_KEY
    end

    def in_phase(phase)
      DEFINITIONS.select { |d| d[:phase] == phase.to_s }
    end

    def label(key, locale = I18n.locale)
      I18n.t("documenter.stages.#{key}", locale: locale, default: key.to_s)
    end

    def phase_label(phase, locale = I18n.locale)
      I18n.t("documenter.phases.#{phase}", locale: locale, default: phase.to_s)
    end

    # THE routing rule. The client never chooses a destination: given where a
    # record is and what it is, exactly one stage comes next.
    #
    #   record_type       - decides whether the design phase applies
    #   has_intersections - decides whether stakeholder review applies
    #
    # Returns nil at the terminal stage.
    def next_key(current_key, record_type:, has_intersections: false)
      return nil if terminal?(current_key)

      case current_key.to_s
      when "s2_confirmation"
        has_intersections ? "s2_stakeholders" : "s2_final"
      when "s2_final"
        DESIGN_TYPES.include?(record_type.to_s) ? "s3_design" : "s4_initial"
      else
        idx = index(current_key)
        return nil if idx.nil?

        # Walk forward past stages this record's route skips, so the plain
        # sequence never drops a Policy into the procedure-design phase.
        candidate = KEYS[idx + 1]
        while candidate && skipped?(candidate, record_type: record_type, has_intersections: has_intersections)
          candidate = KEYS[index(candidate) + 1]
        end
        candidate
      end
    end

    # Stages that are not part of this record's route at all.
    def skipped?(key, record_type:, has_intersections: false)
      case key.to_s
      when "s2_stakeholders" then !has_intersections
      when "s3_design", "s3_designReview" then !DESIGN_TYPES.include?(record_type.to_s)
      else false
      end
    end

    # The full route a record will take, used for progress and the funnel.
    def route_for(record_type:, has_intersections: false)
      KEYS.reject { |k| skipped?(k, record_type: record_type, has_intersections: has_intersections) }
    end

    # True when `to_key` is the single legal forward step from `from_key`.
    def forward?(from_key, to_key, record_type:, has_intersections: false)
      next_key(from_key, record_type: record_type, has_intersections: has_intersections) == to_key.to_s
    end

    # Any earlier stage on this record's route is a legal return target.
    def backward?(from_key, to_key, record_type:, has_intersections: false)
      route = route_for(record_type: record_type, has_intersections: has_intersections)
      from_i = route.index(from_key.to_s)
      to_i = route.index(to_key.to_s)
      return false if from_i.nil? || to_i.nil?

      to_i < from_i
    end
  end
end
