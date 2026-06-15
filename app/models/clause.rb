class Clause < ApplicationRecord
  include PgSearch::Model
  multisearchable(
    against: [ :searchable_content ]
  )

  # Validations
  validates :standard_version_id, presence: true
  validates :code, presence: true, length: { maximum: 100 }
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Associations
  belongs_to :standard_version
  belongs_to :parent, class_name: "Clause", optional: true
  has_many :children, class_name: "Clause", foreign_key: "parent_id", dependent: :destroy
  has_many :clause_translations, dependent: :destroy
  has_many :checklist_items, dependent: :destroy
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload
  has_many :capa_clauses, dependent: :destroy
  has_many :capas, through: :capa_clauses
  has_one :tool_clause, dependent: :destroy
  has_one :tool, through: :tool_clause
  has_many :company_clause_instances, dependent: :destroy
  has_many :clause_score_caches, class_name: "ClauseScoreCache", dependent: :destroy

  # Scopes
  scope :root_clauses, -> { where(parent_id: nil) }
  scope :leaf_clauses, -> { where.not(id: Clause.select(:parent_id).where.not(parent_id: nil).distinct) }
  scope :ordered, -> { order(:sort_order) }

  # Instance methods
  def root?
    parent_id.nil?
  end

  def leaf?
    children.empty?
  end

  # Returns a relation of this clause and all its descendants (for use in place of has_ancestry's self_and_descendants)
  def self_and_descendants
    ids = [id]
    to_process = [id]
    while to_process.any?
      child_ids = Clause.where(parent_id: to_process).pluck(:id)
      ids.concat(child_ids)
      to_process = child_ids
    end
    Clause.where(id: ids)
  end

  def calculated_points
    allocated_points || base_points || 0
  end

  def terminal?
    leaf?
  end

  # The tool covering this clause's subtree. Terminals have at most one
  # ToolClause (DB-level uniqueness on clause_id); parents share that tool with
  # all their terminal descendants because tools are linked at root level and
  # propagated to every terminal.
  def primary_tool
    return tool if leaf?
    descendant_terminal_ids = self_and_descendants
                                .where("NOT EXISTS (SELECT 1 FROM clauses c WHERE c.parent_id = clauses.id)")
                                .pluck(:id)
    ToolClause.where(clause_id: descendant_terminal_ids).limit(1).first&.tool
  end

  # Calculate score for this clause using a specific tool
  # Optionally accepts a company to use cached scores when available
  def calculate_score(tool, company = nil)
    return nil unless tool.present?
    ClauseScoreCalculator.calculate_for_clause(self, tool, company)
  end

  # Get the score data if already calculated (for display optimization)
  def score_data(tool)
    calculate_score(tool)
  end

  def title(language_code = "en")
    translation = clause_translations.find_by(language_code: language_code)
    translation&.title || code
  end

  def summary(language_code = "en")
    translation = clause_translations.find_by(language_code: language_code)
    translation&.summary
  end

  def body(language_code = "en")
    translation = clause_translations.find_by(language_code: language_code)
    translation&.body
  end

  def full_code
    code
  end

  # Build searchable content from code and all translations
  # This method is used by pg_search for indexing
  def searchable_content
    content_parts = [ code ]

    # Add English translations
    en_translation = clause_translations.find_by(language_code: "en")
    if en_translation
      content_parts << en_translation.title if en_translation.title.present?
      content_parts << en_translation.summary if en_translation.summary.present?
      content_parts << en_translation.body if en_translation.body.present?
    end

    # Add Arabic translations (for bilingual search)
    ar_translation = clause_translations.find_by(language_code: "ar")
    if ar_translation
      content_parts << ar_translation.title if ar_translation.title.present?
      content_parts << ar_translation.summary if ar_translation.summary.present?
      content_parts << ar_translation.body if ar_translation.body.present?
    end

    content_parts.join(" ")
  end
end
