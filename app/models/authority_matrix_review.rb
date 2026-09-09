# One person asked to look over a version of the executive matrix before it is
# published, and their answer. The round is complete when everyone accepted;
# the company admin then presses Publish and the version takes effect.
class AuthorityMatrixReview < ApplicationRecord
  DECISIONS = %w[accepted rejected].freeze

  belongs_to :matrix, class_name: "PpRecord"
  belongs_to :user
  belongs_to :requested_by, class_name: "User", optional: true

  validates :requested_at, presence: true
  validates :decision, inclusion: { in: DECISIONS }, allow_blank: true
  validates :comment, length: { maximum: 5000 }
  validates :user_id, uniqueness: { scope: :matrix_id }

  scope :pending, -> { where(decision: nil) }
  scope :accepted, -> { where(decision: "accepted") }
  scope :rejected, -> { where(decision: "rejected") }
  scope :ordered, -> { order(:requested_at) }

  def pending? = decision.nil?
  def accepted? = decision == "accepted"
  def rejected? = decision == "rejected"

  def answer!(decision, comment: nil)
    update!(decision: decision, comment: comment.presence, decided_at: Time.current)
  end
end
