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

  # "Proposed" is a suggestion from the AI that nobody has taken on yet. It is
  # not work until someone keeps it with an owner and a due date.
  enum :status, {
    proposed: "Proposed",
    started: "Started",
    in_progress: "In Progress",
    done: "Done"
  }, default: "Started"

  scope :active, -> { where.not(status: "proposed") }
  scope :proposals, -> { where(status: "proposed") }

  validates :title, presence: true
end
