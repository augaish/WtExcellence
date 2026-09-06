class EvidenceAttachment < ApplicationRecord
  # Validations
  validates :upload_id, presence: true
  validates :attachable_type, presence: true, inclusion: { in: %w[Standard Clause ChecklistItem Capa CapaAction Assessment PpRecord] }
  validates :attachable_id, presence: true
  validates :purpose, length: { maximum: 50 }, allow_blank: true
  validates :upload_id, uniqueness: { scope: [:attachable_type, :attachable_id],
                                        message: "is already linked to this entity" }

  # Associations
  belongs_to :upload
  belongs_to :attachable, polymorphic: true
  belongs_to :attached_by_user, class_name: "User", foreign_key: "attached_by", optional: true

  # Scopes
  scope :for_standard, -> { where(attachable_type: "Standard") }
  scope :for_clause, -> { where(attachable_type: "Clause") }
  scope :for_checklist_item, -> { where(attachable_type: "ChecklistItem") }
  scope :for_capa, -> { where(attachable_type: "Capa") }
  scope :for_assessment, -> { where(attachable_type: "Assessment") }
  scope :for_pp_record, -> { where(attachable_type: "PpRecord") }

  # Instance methods
  def attachable_name(language_code = "en")
    case attachable_type
    when "Standard"
      attachable.display_name(language_code)
    when "Clause"
      attachable.title(language_code) || attachable.code
    when "ChecklistItem"
      attachable.text(language_code) || attachable.code
    when "Capa"
      attachable.title || "Untitled Capa"
    when "CapaAction"
      attachable.title || "Action"
    when "Assessment"
      begin
        clause_code = attachable.tool_clause.clause.code
        "Assessment #{clause_code}"
      rescue
        "Assessment #{attachable.id}"
      end
    else
      "Unknown"
    end
  end

  def attachable_code
    case attachable_type
    when "Standard"
      attachable.code
    when "Clause"
      attachable.full_code
    when "ChecklistItem"
      attachable.code
    when "Capa", "CapaAction", "Assessment"
      nil
    else
      nil
    end
  end
end
