class CapaAction < ApplicationRecord
  belongs_to :capa

  has_many :capa_action_assignments, dependent: :destroy
  has_many :company_users, through: :capa_action_assignments
  has_many :evidence_attachments, as: :attachable, dependent: :destroy
  has_many :linked_uploads, through: :evidence_attachments, source: :upload
  has_many :comments, as: :commentable, dependent: :destroy

  enum :action_type, {
    corrective: "Corrective",
    preventive: "Preventive"
  }

  enum :status, {
    started: "Started",
    in_progress: "In Progress",
    done: "Done"
  }, default: "Started"

  validates :title, presence: true
end
