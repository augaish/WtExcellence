# Clauses were all saved with position 1 (the column's default hid the missing
# assignment). Number them as they were written: by creation order within
# their record and parent.
class RenumberPpRecordClauses < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE pp_record_clauses AS c
      SET position = numbered.rn
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY pp_record_id, parent_id ORDER BY position, created_at, id) AS rn
        FROM pp_record_clauses
      ) AS numbered
      WHERE c.id = numbered.id AND c.position <> numbered.rn
    SQL
  end

  def down; end
end
