class Capa < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :standard, optional: true
  belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

  has_many :capa_assignments, dependent: :destroy
  has_many :company_users, through: :capa_assignments
  has_many :users, through: :company_users
  has_one :questionnaire, dependent: :destroy
  has_many :capa_actions, dependent: :destroy
  has_many :capa_clauses, dependent: :destroy
  has_many :clauses, through: :capa_clauses
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload

  enum :priority, {
    low: "Low",
    medium: "Medium",
    high: "High"
  }

  enum :status, {
    open: "Open",
    assigned: "Assigned",
    in_progress: "In Progress",
    closed: "Closed"
  }, default: "Open"

  validates :title, presence: true
  validates :description, presence: true
  validates :source, presence: true

  scope :archived, -> { where(archived: true) }
  scope :not_archived, -> { where(archived: false) }

  before_create :assign_friendly_id
  after_create :log_creation
  after_update :log_update

  include PgSearch::Model
  multisearchable(
    against: [ :searchable_content ]
  )

  def searchable_content
    content_parts = [ title ]
    content_parts << description if description.present?
    content_parts << standard.code if standard.present?
    content_parts.join(" ")
  end

  def friendly_code
    return nil unless friendly_id && created_at
    "CAPA-#{friendly_id}-#{created_at.strftime('%Y-%m-%d')}"
  end

  def sync_status_with_assignments
    return unless persisted?
    
    has_assignments = capa_assignments.exists?
    
    if has_assignments && open?
      update_column(:status, :assigned)
    elsif !has_assignments && assigned?
      update_column(:status, :open)
    end
  end

  private

  def assign_friendly_id
    return if friendly_id.present? || company_id.blank?

    # Get the maximum friendly_id for this company (including archived)
    max_friendly_id = Capa.where(company_id: company_id)
                          .where.not(friendly_id: nil)
                          .maximum(:friendly_id) || 0

    self.friendly_id = max_friendly_id + 1
  end

  def log_creation
    # Get the current user from Thread storage if available
    performed_by = Thread.current[:current_user]
    
    # Log audit action
    if performed_by && company_id
      AuditLogService.log_action(
        actor_user: performed_by,
        company: company,
        action: 'CREATE_CAPA',
        entity_type: 'capa',
        entity_id: id,
        payload: {
          title: title,
          status: status,
          priority: priority,
          source: source
        }
      )
    end
  end

  def log_update
    # Get the current user from Thread storage if available
    performed_by = Thread.current[:current_user]

    # Track all changes
    changes_to_track = {}

    # Track status changes
    if saved_change_to_status?
      changes_to_track["status"] = [ saved_change_to_status[0], saved_change_to_status[1] ]
    end

    # Track title changes
    if saved_change_to_title?
      changes_to_track["title"] = [ saved_change_to_title[0], saved_change_to_title[1] ]
    end

    # Track description changes
    if saved_change_to_description?
      changes_to_track["description"] = [ saved_change_to_description[0], saved_change_to_description[1] ]
    end

    # Track priority changes
    if saved_change_to_priority?
      changes_to_track["priority"] = [ saved_change_to_priority[0], saved_change_to_priority[1] ]
    end

    # Track due date changes
    if saved_change_to_due_date?
      changes_to_track["due_date"] = [ saved_change_to_due_date[0], saved_change_to_due_date[1] ]
    end

    # Track standard changes
    if saved_change_to_standard_id?
      changes_to_track["standard_id"] = [ saved_change_to_standard_id[0], saved_change_to_standard_id[1] ]
    end

    # Track source changes
    if saved_change_to_source?
      changes_to_track["source"] = [ saved_change_to_source[0], saved_change_to_source[1] ]
    end

    # Track archived changes
    if saved_change_to_archived?
      changes_to_track["archived"] = [ saved_change_to_archived[0], saved_change_to_archived[1] ]
    end

    # Log audit action if there were changes
    if changes_to_track.any? && performed_by && company_id
      AuditLogService.log_action(
        actor_user: performed_by,
        company: company,
        action: 'UPDATE_CAPA',
        entity_type: 'capa',
        entity_id: id,
        payload: { changes: changes_to_track }
      )
    end
  end
end
