class BackfillCapaFriendlyIds < ActiveRecord::Migration[8.0]
  def up
    # Get all companies that have CAPAs
    Company.find_each do |company|
      # Get all CAPAs for this company ordered by creation date (including archived)
      capas = Capa.where(company_id: company.id)
                  .order(:created_at, :id)
                  .where(friendly_id: nil)

      # Assign sequential friendly_ids starting from 1
      capas.each_with_index do |capa, index|
        capa.update_column(:friendly_id, index + 1)
      end
    end
  end

  def down
    # Remove all friendly_ids (set to nil)
    Capa.update_all(friendly_id: nil)
  end
end
