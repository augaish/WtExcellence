# Shared behaviour for GRC records (Risk / Vendor / CustomerCommitment) that can
# be resolved through the QMS CAPA process. Gives each record its linked CAPAs.
module GovernanceCapaLinkable
  extend ActiveSupport::Concern

  included do
    has_many :linked_capas, class_name: "Capa", as: :origin, dependent: :nullify
  end

  # Active (non-archived) CAPAs raised from this governance record.
  def open_linked_capas
    linked_capas.not_archived.where.not(status: "Closed")
  end
end
