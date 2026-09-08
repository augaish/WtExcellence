require "test_helper"

# The seeds create demo accounts including a platform super admin, with a shared
# password. Running them outside development would put those accounts into a
# live system, so the file refuses rather than relying on nobody making that
# mistake.
class SeedsGuardTest < ActiveSupport::TestCase
  SEEDS = Rails.root.join("db/seeds.rb")

  test "the seeds refuse to run outside development unless explicitly allowed" do
    source = File.read(SEEDS)

    assert_match(/Rails\.env\.development\?/, source)
    assert_match(/SEEDS_ALLOW_NON_DEVELOPMENT/, source)
    assert_match(/abort/, source)
  end

  test "no account password is written into the file" do
    source = File.read(SEEDS)
    assignments = source.scan(/user\.password(?:_confirmation)?\s*=\s*(.+)/).flatten

    assert_predicate assignments, :any?, "the seeds should still create accounts"
    assignments.each do |assignment|
      assert_equal "SEED_PASSWORD", assignment.strip,
        "a literal password in the repository is readable by anyone with access"
    end
  end

  test "the seeds do not print the password they used" do
    assert_no_match(/password: /, File.read(SEEDS))
  end
end
