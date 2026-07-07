class DashboardLayout < ApplicationRecord
  belongs_to :company, optional: true

  # Ordered list of every movable/hideable widget on the overview. The stored
  # config records the user's chosen order and which widgets are hidden; any
  # widget not present in the stored order falls back to this canonical order
  # (so newly-shipped widgets appear automatically).
  WIDGET_KEYS = %w[
    top_metrics second_metrics charts governance risk_matrix commitments
    compliance_gauge compliance_by_standard risks_by_workspace trust_center tables
  ].freeze
  SLOTS = (1..3).to_a.freeze

  scope :platform, -> { where(scope: "platform") }
  scope :for_company, ->(company_id) { where(scope: "company", company_id: company_id) }

  validates :slot, inclusion: { in: SLOTS }
  validates :scope, inclusion: { in: %w[company platform] }

  # Returns the ordered, de-duplicated widget list for rendering — stored order
  # first (filtered to known keys), then any widgets the stored config predates.
  def ordered_widgets
    stored = Array(config["order"]).select { |k| WIDGET_KEYS.include?(k) }
    (stored + (WIDGET_KEYS - stored)).uniq
  end

  def hidden_widgets
    Array(config["hidden"]).select { |k| WIDGET_KEYS.include?(k) }
  end

  def widget_visible?(key)
    !hidden_widgets.include?(key)
  end

  # Fetch (or lazily build, unsaved) the layout for a given scope/company/slot.
  def self.resolve(scope:, company_id:, slot:)
    slot = slot.to_i
    slot = 1 unless SLOTS.include?(slot)
    rel = scope == "platform" ? platform : for_company(company_id)
    rel.find_by(slot: slot) || new(scope: scope, company_id: (scope == "platform" ? nil : company_id), slot: slot, config: {})
  end

  # The active slot for a scope/company, defaulting to 1.
  def self.active_slot(scope:, company_id:)
    rel = scope == "platform" ? platform : for_company(company_id)
    rel.where(is_active: true).order(:slot).first&.slot || 1
  end
end
