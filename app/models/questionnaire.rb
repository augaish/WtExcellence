class Questionnaire < ApplicationRecord
  belongs_to :capa

  validates :capa_id, presence: true, uniqueness: true
end
