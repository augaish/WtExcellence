class ChecklistItem < ApplicationRecord
  include PgSearch::Model
  multisearchable(
    against: [ :searchable_content ],
    using: {
      tsearch: {},                    # Full-text search (removes prefix restriction for word matching)
      trigram: { threshold: 0.3 }    # Trigram matching for substring search anywhere in text
    }
  )

  # Validations
  validates :clause_id, presence: true
  validates :item_type, presence: true, inclusion: { in: %w[requirement question control note] }
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Associations
  belongs_to :clause
  has_many :checklist_item_translations, dependent: :destroy
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload
  has_many :company_checklist_item_instances, dependent: :destroy
  has_many :checkpoint_summaries, dependent: :destroy

  # Scopes
  scope :requirements, -> { where(item_type: "requirement") }
  scope :questions, -> { where(item_type: "question") }
  scope :controls, -> { where(item_type: "control") }
  scope :notes, -> { where(item_type: "note") }
  scope :ordered, -> { order(:sort_order) }

  # Instance methods
  def requirement?
    item_type == "requirement"
  end

  def question?
    item_type == "question"
  end

  def control?
    item_type == "control"
  end

  def note?
    item_type == "note"
  end

  # Requested language first, then any other language with content — an
  # Arabic-only extraction must still show checkpoints in the English UI.
  def text(language_code = "en")
    own = checklist_item_translations.find_by(language_code: language_code)&.text
    return own if own.present?

    checklist_item_translations.where.not(language_code: language_code)
                               .where.not(text: [ nil, "" ]).first&.text
  end

  def guidance(language_code = "en")
    own = checklist_item_translations.find_by(language_code: language_code)&.guidance
    return own if own.present?

    checklist_item_translations.where.not(language_code: language_code)
                               .where.not(guidance: [ nil, "" ]).first&.guidance
  end

  # Build searchable content from code and all translations
  # This method is used by pg_search for indexing
  def searchable_content
    content_parts = [ code ]

    # Add English translations
    en_translation = checklist_item_translations.find_by(language_code: "en")
    if en_translation
      content_parts << en_translation.text if en_translation.text.present?
      content_parts << en_translation.guidance if en_translation.guidance.present?
    end

    # Add Arabic translations (for bilingual search)
    ar_translation = checklist_item_translations.find_by(language_code: "ar")
    if ar_translation
      content_parts << ar_translation.text if ar_translation.text.present?
      content_parts << ar_translation.guidance if ar_translation.guidance.present?
    end

    content_parts.join(" ")
  end
end
