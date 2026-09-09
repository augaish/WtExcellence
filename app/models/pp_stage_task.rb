# A piece of a stage's work handed to one person: the reporter who fills the
# clauses, the team member who reviews them, the designer who draws the
# diagram, the publisher who posts the document. It is open until the person
# submits it back to whoever handed it out.
class PpStageTask < ApplicationRecord
  belongs_to :pp_record, class_name: "PpRecord"
  belongs_to :user
  belongs_to :assigned_by, class_name: "User", optional: true

  validates :stage_key, presence: true, inclusion: { in: PpStage::KEYS }
  validates :assigned_at, presence: true
  validates :note, length: { maximum: 2000 }

  scope :for_stage, ->(key) { where(stage_key: key) }
  scope :open, -> { where(submitted_at: nil) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  def open?
    submitted_at.nil?
  end

  def submit!(note: nil)
    update!(submitted_at: Time.current, note: note.presence || self.note)
  end
end
