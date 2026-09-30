# The reviewer can send an assessment back for rework with a reason, instead
# of only signing it off.
class AddReworkToVendorAssessments < ActiveRecord::Migration[8.0]
  def change
    add_column :vendor_assessments, :returned_at, :datetime
    add_column :vendor_assessments, :return_reason, :text
    add_reference :vendor_assessments, :returned_by, type: :uuid, foreign_key: { to_table: :users }, null: true
  end
end
