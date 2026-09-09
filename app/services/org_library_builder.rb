# Mirrors the organization structure into the Library: one folder per unit,
# nested the way the units report. Published documents are later filed into
# the folder of the unit that owns them, so the two trees must agree.
#
# Safe to run again and again. A folder remembers the unit it was built from;
# a rebuild renames and re-parents it to follow the structure, creates folders
# for new units, and never deletes anything — a folder may hold files that
# outlive a unit.
class OrgLibraryBuilder
  Result = Struct.new(:created, :updated, keyword_init: true) do
    def total = created + updated
  end

  def self.build(company, user:, locale: I18n.locale)
    new(company, user: user, locale: locale).build
  end

  def initialize(company, user:, locale: I18n.locale)
    @company = company
    @user = user
    @locale = locale
    @result = Result.new(created: 0, updated: 0)
  end

  def build
    Folder.transaction do
      units_by_parent = company.org_units.active.order(:sort_order, :created_at).group_by(&:parent_id)
      # Roots first so a child can always find its parent's folder.
      walk(units_by_parent, parent_id: nil, parent_folder: nil)
    end
    result
  end

  private

  attr_reader :company, :user, :locale, :result

  def walk(units_by_parent, parent_id:, parent_folder:)
    (units_by_parent[parent_id] || []).each do |unit|
      folder = sync_folder(unit, parent_folder)
      walk(units_by_parent, parent_id: unit.id, parent_folder: folder)
    end
  end

  def sync_folder(unit, parent_folder)
    attributes = {
      name: unit.display_name(locale).presence || unit.code.presence || unit.id,
      color: unit.org_group&.color.presence || Folder.column_defaults["color"],
      parent: parent_folder,
      company_id: company.id
    }

    folder = Folder.find_by(org_unit_id: unit.id)
    if folder
      folder.assign_attributes(attributes)
      if folder.changed?
        folder.save!
        result.updated += 1
      end
      folder
    else
      result.created += 1
      Folder.create!(attributes.merge(org_unit: unit, created_by: user&.id))
    end
  end
end
