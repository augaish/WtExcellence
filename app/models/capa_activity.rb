class CapaActivity < ApplicationRecord
  belongs_to :capa
  belongs_to :performed_by, class_name: "User", foreign_key: "performed_by_id", optional: true
end
