# One decision inside a procedure, and who holds each level of authority over it
# (مصفوفة الصلاحيات الإجرائية).
#
# This is the operational tier. It must stay consistent with the company's
# Executive DoA, which is what Phase E's conformance check will verify — the
# job Institutional Excellence does today by reading two spreadsheets side by
# side.
class PpProcessAuthority < ApplicationRecord
  belongs_to :pp_process, class_name: "PpProcess"

  has_many :assignments, -> { ordered }, class_name: "PpAuthorityAssignment",
    foreign_key: "pp_process_authority_id", dependent: :destroy

  validates :item, length: { maximum: 300 }
  validates :decision, length: { maximum: 300 }
  validate :must_describe_a_decision

  scope :ordered, -> { order(:sort_order, :created_at) }

  # Exactly one holder may carry the final authorization for a decision — that
  # is what «صاحب الصلاحية» means. Zero means nobody can decide it; more than
  # one means nobody knows who does.
  def authorizers
    assignments.select { |assignment| assignment.level == AuthorityLevel::FINAL_KEY }
  end

  def single_authorizer?
    authorizers.size == 1
  end

  # A holder carrying preparation, review and final authorization over the same
  # decision breaches «لا يجوز للموظف نفسه الجمع بين مهام الإعداد والمراجعة
  # والموافقة لنفس الإجراء». Returns the holders in breach.
  def segregation_breaches
    assignments.group_by(&:holder_key).filter_map do |holder_key, held|
      next if holder_key.blank?

      holder_key if AuthorityLevel.segregation_conflict?(held.map(&:level))
    end
  end

  private

  def must_describe_a_decision
    return if item.present? || decision.present?

    errors.add(:decision, I18n.t("process_authorities.errors.decision_required"))
  end
end
