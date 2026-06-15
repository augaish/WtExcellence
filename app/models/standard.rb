class Standard < ApplicationRecord
  include PgSearch::Model
  multisearchable(
    against: [ :code ]
  )


  PIPELINE_TYPES = %w[efqm iso9001 qiyas generic].freeze

  # Validations
  validates :code, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :is_primary, inclusion: { in: [ true, false ] }
  validates :pipeline_type, inclusion: { in: PIPELINE_TYPES }, allow_nil: true

  # Associations (company_standards before standard_versions so they are destroyed first;
  # otherwise StandardVersion#dependent: :nullify would set active_version_id = NULL and violate NOT NULL)
  has_many :standard_translations, dependent: :destroy
  has_many :company_standards, dependent: :destroy
  has_many :standard_versions, dependent: :destroy
  has_many :capas, dependent: :nullify
  has_many :ingestion_jobs, dependent: :destroy
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload

  # Scopes
  scope :primary, -> { where(is_primary: true) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def primary?
    is_primary
  end

  def latest_version
    standard_versions.order(:created_at).last
  end

  def display_name(language_code = "en")
    translation = standard_translations.find_by(language_code: language_code)
    translation&.name || code
  end

  def description(language_code = "en")
    translation = standard_translations.find_by(language_code: language_code)
    translation&.description
  end
end
