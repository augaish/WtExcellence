# The Process Architecture becomes Level 0 (three fixed bands) → Level 1 →
# Level 2, with procedures living in Records as level 3. Everything in the
# process tables so far was test data, and the product owner asked for it to
# be cleared rather than converted, so the tables are emptied here.
class ResetProcessArchitectureToTwoLevels < ActiveRecord::Migration[8.0]
  def up
    # Records keep their rows; only the link to a process is dropped.
    execute "UPDATE pp_records SET pp_process_id = NULL WHERE pp_process_id IS NOT NULL"

    # Diagrams drawn for a process, and their elements and flows.
    execute <<~SQL
      DELETE FROM pp_diagram_flows WHERE pp_diagram_id IN (SELECT id FROM pp_diagrams WHERE owner_type = 'PpProcess');
      DELETE FROM pp_diagram_elements WHERE pp_diagram_id IN (SELECT id FROM pp_diagrams WHERE owner_type = 'PpProcess');
      DELETE FROM pp_diagrams WHERE owner_type = 'PpProcess';
      DELETE FROM pp_authority_assignments;
      DELETE FROM pp_process_authorities;
      DELETE FROM pp_process_steps;
      DELETE FROM pp_processes;
    SQL

    # Position within the parent (or within the band for level 1). It forms the
    # architecture number, e.g. 1.2 or 1.2.4, that procedure codes build on.
    add_column :pp_processes, :number, :integer

    # The three Level 0 bands are fixed, but a company may rename them, and the
    # objective shown beside the map is the company's own.
    add_column :companies, :process_band_names, :jsonb, null: false, default: {}
    add_column :companies, :process_objective_en, :string, limit: 300
    add_column :companies, :process_objective_ar, :string, limit: 300
  end

  def down
    remove_column :companies, :process_objective_ar
    remove_column :companies, :process_objective_en
    remove_column :companies, :process_band_names
    remove_column :pp_processes, :number
  end
end
