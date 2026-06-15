class CapaActionAssignment < ApplicationRecord
  belongs_to :capa_action
  belongs_to :company_user

  validates :capa_action_id, uniqueness: { scope: :company_user_id }
end
