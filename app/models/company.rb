class Company < ApplicationRecord
  # Toggleable per-company modules. Keys are stable identifiers; label_key is the
  # i18n key for the human name. A module with a :column is stored on the
  # companies table (e.g. trust_center) rather than in company_modules, so the
  # existing feature keeps its single source of truth. Core areas (Overview,
  # Account Management, General Settings) are intentionally NOT listed — they are
  # always available.
  MODULES = {
    standards:       { label_key: "standards" },
    library:         { label_key: "library" },
    capa:            { label_key: "capa_management" },
    risk:            { label_key: "risk_management" },
    vendors:         { label_key: "vendor_management" },
    commitments:     { label_key: "customer_commitments" },
    org_structure:   { label_key: "org_structure.title" },
    processes:       { label_key: "process_architecture.title" },
    pp:              { label_key: "pp.title" },
    authorities:     { label_key: "doa.title" },
    trust_center:    { label_key: "trust_center", column: :trust_center_enabled },
    ai_instructions: { label_key: "ai_instructions" },
    tools:           { label_key: "tool_setup" }
  }.freeze

  def self.module_keys
    MODULES.keys.map(&:to_s)
  end

  has_many :company_users, dependent: :destroy
  has_many :company_modules, dependent: :destroy
  has_many :org_level_definitions, -> { order(:level) }, dependent: :destroy
  has_many :org_groups, -> { order(:sort_order) }, dependent: :destroy
  has_many :org_units, dependent: :destroy
  has_many :pp_processes, dependent: :destroy
  has_many :pp_packages, dependent: :destroy
  has_many :pp_records, dependent: :destroy
  has_many :pp_stage_targets, dependent: :destroy
  has_many :glossary_terms, -> { ordered }, dependent: :destroy
  has_many :authority_categories, -> { ordered }, dependent: :destroy
  has_many :authorities, -> { ordered }, dependent: :destroy
  has_many :authority_delegations, -> { ordered }, dependent: :destroy
  has_many :company_holidays, -> { order(:start_date) }, dependent: :destroy
  has_many :pp_diagrams, dependent: :destroy
  has_many :users, through: :company_users
  has_many :capas, dependent: :nullify
  has_many :company_standards, dependent: :destroy
  has_many :risk_workspaces, dependent: :destroy
  # Risks hung off the company only through their workspace, unlike vendors and
  # commitments, so there was no way to ask a company for its risks.
  has_many :risks, dependent: :destroy
  has_many :customer_commitments, dependent: :destroy
  has_many :vendors, dependent: :destroy
  has_many :ai_instructions, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :uploads, dependent: :destroy
  has_many :clause_score_caches, class_name: "ClauseScoreCache", dependent: :destroy

  # Company branding, set by the company admin. Colours are stored as hex; the
  # palette decides whether one is actually usable.
  has_one_attached :brand_logo

  validates :name, presence: true, length: { maximum: 200 }
  validates :brand_primary_color, :brand_accent_color,
    format: { with: BrandPalette::HEX_PATTERN, message: :invalid }, allow_blank: true
  validates :license_seats, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :credits, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :default_locale, length: { maximum: 10 }

  scope :active, -> { where(is_active: true) }
  scope :pending, -> { where(status: "pending") }

  # Get the admin company user (admin@example.com) for this company
  def admin_company_user
    admin_user = User.find_by(email: "admin@example.com")
    return nil unless admin_user

    company_users.find_by(user: admin_user)
  end

  # True unless a super admin has explicitly disabled the module. Unknown keys
  # are treated as enabled (never gate on a typo). Column-backed modules
  # (trust_center) read their boolean column.
  def module_enabled?(key)
    meta = MODULES[key.to_sym]
    return true if meta.nil?
    return !!public_send(meta[:column]) if meta[:column]

    module_settings.fetch(key.to_s, true)
  end

  # Enable/disable a module for this company. Column-backed modules update their
  # column; the rest upsert a company_modules row.
  def set_module!(key, enabled)
    meta = MODULES[key.to_sym]
    raise ArgumentError, "Unknown module: #{key}" if meta.nil?

    if meta[:column]
      update!(meta[:column] => enabled)
    else
      record = company_modules.find_or_initialize_by(module_key: key.to_s)
      record.update!(enabled: enabled)
    end
    @module_settings = nil
    enabled
  end

  # The colours to render for this company, falling back to the WTE palette.
  # Level 0 of the Process Architecture: fixed bands the company may rename.
  def process_band_name(band, locale = I18n.locale)
    names = process_band_names.fetch(band.to_s, {})
    names[locale.to_s].presence || names[(locale.to_s == "ar" ? "en" : "ar")].presence ||
      I18n.t("process_architecture.categories.#{band}", locale: locale)
  end

  def process_objective(locale = I18n.locale)
    primary, fallback = locale.to_s == "ar" ? [ process_objective_ar, process_objective_en ] : [ process_objective_en, process_objective_ar ]
    primary.presence || fallback.presence
  end

  def brand_palette
    @brand_palette ||= BrandPalette.new(self)
  end

  def pending?
    status == "pending"
  end

  def active_status?
    status == "active"
  end

  # { "s2_prep" => 10, ... } for the stages this company has configured.
  def stage_target_days
    @stage_target_days ||= pp_stage_targets.pluck(:stage_key, :target_days).to_h
  end

  # Clear the memoized module settings when the record is reloaded, so a
  # module_enabled? call after reload reflects the database.
  def reload(*)
    @module_settings = nil
    @stage_target_days = nil
    @brand_palette = nil
    super
  end

  private

  # One query per request, memoized: { "capa" => false, ... } for rows that exist.
  def module_settings
    @module_settings ||= company_modules.pluck(:module_key, :enabled).to_h
  end
end
