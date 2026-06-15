class CapaClause < ApplicationRecord
  belongs_to :capa
  belongs_to :clause

  validates :capa_id, uniqueness: { scope: :clause_id }
end
