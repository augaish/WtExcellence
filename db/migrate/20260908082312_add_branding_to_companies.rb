class AddBrandingToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Company branding, set by the company admin. The logo is an Active Storage
    # attachment; only the colours need columns. Null means "use the WTE
    # palette", so a company that sets nothing looks exactly as it does today.
    add_column :companies, :brand_primary_color, :string, limit: 7
    add_column :companies, :brand_accent_color, :string, limit: 7
  end
end
