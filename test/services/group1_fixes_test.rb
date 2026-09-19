require "test_helper"

# Test team items 19, 17 and 22.
class Group1FixesTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "G1 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "g1-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Author", is_active: true)
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
  end

  test "19: clauses and sub-clauses are numbered in sequence" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Numbered", description: "x")
    a = policy.clauses.create!(title: "A")
    b = policy.clauses.create!(title: "B")
    3.times { |i| policy.clauses.create!(title: "A#{i}", parent: a) }
    policy.clauses.create!(title: "B0", parent: b)

    policy.clauses.reload
    numbers = policy.clauses.main.flat_map { |m| [ m.number ] + m.children.map(&:number) }
    assert_equal %w[1 1.1 1.2 1.3 2 2.1], numbers
  end

  test "17: the next version carries clauses, steps, decisions, references and terms" do
    level1 = @company.pp_processes.create!(name_en: "Ops", level: 1, category: "core")
    process = @company.pp_processes.create!(name_en: "Review", level: 2, parent: level1)
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Proc", pp_process: process,
      current_stage: PpStage::TERMINAL_KEYS.first, published_at: Time.current, code: "PROC-GEN-1.1.1-V1")
    main = procedure.clauses.create!(title: "Scope", body: "All")
    procedure.clauses.create!(title: "Detail", parent: main)
    step = procedure.steps.create!(position: 1, activity: "Receive", responsible_title: "Clerk")
    decision = procedure.operational_authorities.create!(item: "Approve request", pp_process_step: step)
    decision.assignments.create!(level: "authorize", holder_title: "Manager")
    procedure.references.create!(name: "ISO 9001", source: "Standard")

    successor = RecordVersionService.new(procedure, actor: @user).open_next

    assert_equal [ "1 Scope", "1.1 Detail" ], successor.clauses.ordered.map { |c| "#{c.number} #{c.title}" }
    assert_equal [ "Receive" ], successor.steps.map(&:activity)
    copied_decision = successor.operational_authorities.sole
    assert_equal successor.steps.sole.id, copied_decision.pp_process_step_id
    assert_equal [ "Manager" ], copied_decision.assignments.map(&:holder_title)
    assert_equal [ "ISO 9001" ], successor.references.map(&:name)
    assert_equal 1, procedure.reload.steps.count, "the old version keeps its own content"
  end

  test "22: the Word file contains the clauses" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Word Policy", description: "x")
    main = policy.clauses.create!(title: "Purpose", body: "Why we exist")
    policy.clauses.create!(title: "Detail", body: "More", parent: main)

    docx = RecordDocxRenderer.new(RecordDocument.new(policy, locale: :en)).render
    xml = nil
    Zip::File.open_buffer(StringIO.new(docx)) { |zip| xml = zip.read("word/document.xml") }
    assert_includes xml, "1 Purpose"
    assert_includes xml, "Why we exist"
    assert_includes xml, "1.1 Detail"
  end
end
