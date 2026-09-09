# The document lifecycle, exactly as the product owner specified it.
#
# This is CONFIGURATION, not a table: the sequence is fixed, so it lives in code
# where it can be reasoned about and tested. What varies per company (target
# days) lives in pp_stage_targets.
#
# Three routes share one vocabulary of stages:
#
#   policy / form / service:
#     verify → approved → prep → draftReview → stakeholders → final → toPublish → published
#   procedure:
#     the same, with design → designReview between stakeholders and final
#   glossary:
#     submitted → published (one approval by a P&P Manager)
#
# Each stage names who acts in it (`actor`), which is what the worklists and
# the permission checks read:
#   :verifier      the contributor chosen when the record was logged
#   :pp_manager    a quality manager flagged as P&P Manager (or a task holder
#                  they picked from their team)
#   :unit_head     the head of the owning unit (or the reporter they assigned)
#   :approvers     the unit heads named in the approval chain
#   :publisher     the person assigned to post the document
#
# No date is ever typed. Every timestamp is stamped by the system when the
# action happens, so durations cannot drift from reality.
class PpStage
  PHASES = %w[inventory preparation documentation approval publishing].freeze

  # kind:
  #   :plain     - move forward, nothing captured
  #   :approval  - holds a chain of unit-head approvals; complete when every
  #                unit has approved (or been auto-approved)
  #   :publish   - captures how the document goes out
  #   :terminal  - the end
  DEFINITIONS = [
    { key: "s1_verify",       phase: "inventory",     kind: :plain,    actor: :verifier,   level: "review" },
    { key: "s1_approved",     phase: "inventory",     kind: :plain,    actor: :pp_manager, level: "approve" },

    { key: "s2_prep",         phase: "preparation",   kind: :plain,    actor: :unit_head,  level: "prepare" },
    { key: "s2_draftReview",  phase: "preparation",   kind: :plain,    actor: :pp_manager, level: "review" },
    { key: "s2_stakeholders", phase: "preparation",   kind: :approval, actor: :approvers,  level: "approve" },

    { key: "s3_design",       phase: "documentation", kind: :plain,    actor: :pp_manager, level: "prepare" },
    { key: "s3_designReview", phase: "documentation", kind: :plain,    actor: :pp_manager, level: "review" },

    { key: "s4_final",        phase: "approval",      kind: :approval, actor: :approvers,  level: "authorize" },

    { key: "s5_toPublish",    phase: "publishing",    kind: :publish,  actor: :publisher,  level: "prepare" },
    { key: "s5_published",    phase: "publishing",    kind: :terminal, actor: nil,         level: "inform" },

    # Glossary only.
    { key: "g1_submitted",    phase: "approval",      kind: :plain,    actor: :pp_manager, level: "approve" },
    { key: "g2_published",    phase: "publishing",    kind: :terminal, actor: nil,         level: "inform" }
  ].freeze

  KEYS = DEFINITIONS.map { |d| d[:key] }.freeze

  DOCUMENT_ROUTE = %w[s1_verify s1_approved s2_prep s2_draftReview s2_stakeholders s4_final s5_toPublish s5_published].freeze
  PROCEDURE_ROUTE = %w[s1_verify s1_approved s2_prep s2_draftReview s2_stakeholders s3_design s3_designReview s4_final s5_toPublish s5_published].freeze
  GLOSSARY_ROUTE = %w[g1_submitted g2_published].freeze

  TERMINAL_KEYS = %w[s5_published g2_published].freeze
  FIRST_KEY = DOCUMENT_ROUTE.first

  # Types that go through the procedure-design pair.
  DESIGN_TYPES = %w[procedure].freeze

  # Stages where the content (clauses or steps) is written or reviewed.
  CONTENT_STAGES = %w[s2_prep s2_draftReview].freeze

  # Sensible starting targets (working days), overridable per company.
  DEFAULT_TARGET_DAYS = {
    "s1_verify" => 3, "s1_approved" => 3,
    "s2_prep" => 10, "s2_draftReview" => 5, "s2_stakeholders" => 10,
    "s3_design" => 10, "s3_designReview" => 5,
    "s4_final" => 10,
    "s5_toPublish" => 3, "s5_published" => 0,
    "g1_submitted" => 3, "g2_published" => 0
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

    def actor_of(key)
      find(key)&.fetch(:actor, nil)
    end

    # The AuthorityLevel this stage exercises.
    def level_of(key)
      find(key)&.fetch(:level, nil)
    end

    def approval_stage?(key)
      kind_of(key) == :approval
    end

    def publish_stage?(key)
      kind_of(key) == :publish
    end

    def terminal?(key)
      TERMINAL_KEYS.include?(key.to_s)
    end

    def content_stage?(key)
      CONTENT_STAGES.include?(key.to_s)
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

    # The full route a record takes, decided by its type alone.
    def route_for(record_type:, **)
      case record_type.to_s
      when "glossary" then GLOSSARY_ROUTE
      when *DESIGN_TYPES then PROCEDURE_ROUTE
      else DOCUMENT_ROUTE
      end
    end

    def first_key_for(record_type)
      route_for(record_type: record_type).first
    end

    # THE routing rule. The client never chooses a destination: given where a
    # record is and what it is, exactly one stage comes next. nil at the end.
    def next_key(current_key, record_type:, **)
      route = route_for(record_type: record_type)
      idx = route.index(current_key.to_s)
      return nil if idx.nil?

      route[idx + 1]
    end

    def previous_key(current_key, record_type:)
      route = route_for(record_type: record_type)
      idx = route.index(current_key.to_s)
      return nil if idx.nil? || idx.zero?

      route[idx - 1]
    end

    # True when `to_key` is the single legal forward step from `from_key`.
    def forward?(from_key, to_key, record_type:, **)
      next_key(from_key, record_type: record_type) == to_key.to_s
    end

    # Any earlier stage on this record's route is a legal return target.
    def backward?(from_key, to_key, record_type:, **)
      route = route_for(record_type: record_type)
      from_i = route.index(from_key.to_s)
      to_i = route.index(to_key.to_s)
      return false if from_i.nil? || to_i.nil?

      to_i < from_i
    end
  end
end
