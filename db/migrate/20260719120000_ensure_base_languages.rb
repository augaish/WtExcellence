class EnsureBaseLanguages < ActiveRecord::Migration[8.0]
  # Clause/standard/checkpoint translations all belong_to a Language row
  # (by language_code). Production was missing the en/ar rows, so every
  # translation failed validation ("Language must exist") and clause trees
  # saved with no titles — the long-standing empty-tree bug.
  #
  # Guarantee the base languages always exist. Idempotent (ON CONFLICT DO
  # NOTHING), so it is safe on every deploy and on a freshly rebuilt database.
  def up
    execute <<~SQL
      INSERT INTO languages (id, code, name, direction, created_at, updated_at)
      VALUES
        (gen_random_uuid(), 'en', 'English', 'ltr', now(), now()),
        (gen_random_uuid(), 'ar', 'Arabic', 'rtl', now(), now())
      ON CONFLICT (code) DO NOTHING
    SQL
  end

  def down
    # Intentionally a no-op: base languages must never be removed.
  end
end
