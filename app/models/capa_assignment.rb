class CapaAssignment < ApplicationRecord
  belongs_to :capa
  belongs_to :company_user
  
  validates :capa_id, uniqueness: { scope: :company_user_id }
  
  after_create :sync_capa_status
  after_destroy :sync_capa_status
  
  private
  
  def sync_capa_status
    capa.sync_status_with_assignments
  end
end

