# A reviewer's note on one authority, left during the approval round of a
# matrix version. The owner (admin or Governance Manager) answers it with
# accept or reject and says why; an answered comment counts as done.
class AuthorityReviewComment < ApplicationRecord
  DECISIONS = %w[accepted rejected].freeze

  belongs_to :matrix, class_name: "PpRecord"
  belongs_to :authority
  belongs_to :user
  belongs_to :replied_by, class_name: "User", optional: true

  validates :body, presence: true, length: { maximum: 5000 }
  validates :decision, inclusion: { in: DECISIONS }, allow_nil: true
  validates :reply, length: { maximum: 5000 }
  # An answer without a reason is not an answer the reviewer can learn from.
  validates :reply, presence: true, if: :answered?

  scope :open, -> { where(replied_at: nil) }
  scope :ordered, -> { order(:created_at) }

  def answered?
    decision.present?
  end
end
