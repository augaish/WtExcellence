require "test_helper"

class Dashboard::AuthoritiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "DoA Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("doa-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("doa-viewer", CompanyUser::ROLES[:company_viewer])

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA 2026")
    @category = @company.authority_categories.create!(name_en: "Contracting")
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a company with no matrix is told how to start one" do
    @matrix.destroy
    sign_in @admin
    get dashboard_authorities_path

    assert_response :success
    assert_includes response.body, I18n.t("doa.empty_start")
    assert_select "form[action=?]", dashboard_create_authority_category_path
  end

  test "starting over shows only the category just added, not those of a deleted matrix" do
    @matrix.destroy
    sign_in @admin
    post dashboard_create_authority_category_path, params: { authority_category: { name_en: "Fresh" } }
    follow_redirect!
    assert_equal [ "Fresh" ], @company.authority_categories.reload.map(&:name_en)
    assert_select "[data-authority-matrix-target=category]", 1
  end

  test "the first category creates version 1 of the matrix" do
    @matrix.destroy
    sign_in @admin
    assert_difference -> { @company.pp_records.of_type("executive_doa").count }, 1 do
      post dashboard_create_authority_category_path, params: { authority_category: { name_en: "Financial" } }
    end
    matrix = @company.pp_records.of_type("executive_doa").sole
    assert_equal 1, matrix.version_number
    assert_redirected_to dashboard_authorities_path(matrix_id: matrix.id)
  end

  test "categories are numbered by position and reordered by drag" do
    sign_in @admin
    second = @company.authority_categories.create!(name_en: "Second")
    assert_equal [ 1, 2 ], [ @category.reload.number, second.number ]

    patch dashboard_reorder_authority_categories_path(matrix_id: @matrix.id), params: { ids: [ second.id, @category.id ] }, as: :json
    assert_response :no_content
    assert_equal [ 2, 1 ], [ @category.reload.number, second.reload.number ]
  end

  test "a Governance Manager may manage; a plain risk manager or quality manager may only read" do
    rm = create_user("doa-rm", CompanyUser::ROLES[:company_risk_manager])
    qm = create_user("doa-qm", CompanyUser::ROLES[:company_quality_manager])
    [ rm, qm ].each do |user|
      sign_in user
      post dashboard_create_authority_category_path, params: { matrix_id: @matrix.id, authority_category: { name_en: "Sneak" } }
      assert_redirected_to dashboard_authorities_path
      sign_out user
    end
    rm.company_user.update!(gov_manager: true)
    sign_in rm
    post dashboard_create_authority_category_path, params: { matrix_id: @matrix.id, authority_category: { name_en: "Allowed" } }
    assert @company.authority_categories.exists?(name_en: "Allowed")
    get dashboard_authorities_path
    assert_select "input[type=search]"
  end

  test "an authority is numbered category.position and has no limit box" do
    sign_in @admin
    post dashboard_create_authority_path, params: { matrix_id: @matrix.id,
      authority: { authority_category_id: @category.id, name_en: "Direct purchase up to SAR 100,000" } }
    follow_redirect!
    assert_select "[data-number]", text: "#{@category.number}.1"
    assert_select "input[name='authority[limit_text]']", 0
    assert_select "select[name='authority[basis_record_id]']", 0
    assert_not_includes response.body, I18n.t("doa.add_band")
  end

  test "authorities are reordered and moved between categories by drag" do
    other = @company.authority_categories.create!(name_en: "Finance")
    first = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "One", number: 1, sort_order: 1)
    second = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Two", number: 2, sort_order: 2)

    sign_in @admin
    patch dashboard_reorder_authorities_path(matrix_id: @matrix.id), params: { ids: [ second.id, first.id ], category_id: other.id }, as: :json
    assert_response :no_content

    assert_equal [ 1, other.id ], [ second.reload.sort_order, second.authority_category_id ]
    assert_equal [ 2, other.id ], [ first.reload.sort_order, first.authority_category_id ]
    numbers = Authority.numbered(@matrix.authorities.ordered.to_a)
    assert_equal "#{other.number}.1", numbers[second.id]
    assert_equal "#{other.number}.2", numbers[first.id]
  end

  test "the pencil edits the name in the page's language, in place" do
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign", name_ar: "توقيع")
    sign_in @admin

    get dashboard_authorities_path
    assert_select "[data-controller=inline-edit] form[hidden] input[name='authority[name_en]'][value=Sign]"
    assert_select "[data-controller=inline-edit] form[hidden] input[name='authority[name_ar]']", 0

    get dashboard_authorities_path(locale: :ar)
    assert_select "form[hidden] input[name='authority[name_ar]'][value=توقيع]"

    patch dashboard_update_authority_path(authority, matrix_id: @matrix.id), params: { authority: { name_en: "Sign contracts" } }
    assert_equal [ "Sign contracts", "توقيع" ], [ authority.reload.name_en, authority.name_ar ]
  end

  test "an older version is read-only and the picker names versions only" do
    older = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Old")
    @matrix.update!(current_stage: PpStage::TERMINAL_KEYS.first, published_at: Time.current)
    sign_in @admin
    post dashboard_open_next_authority_version_path(matrix_id: @matrix.id)
    newest = @company.pp_records.of_type("executive_doa").order(:version_number).last

    get dashboard_authorities_path(matrix_id: @matrix.id)
    assert_select "option", text: "V1 · #{I18n.t('doa.review.published_on', date: I18n.l(Date.current, format: :document))}"
    assert_select "option", text: "V2 · #{I18n.t('doa.versions.current')}"
    assert_select "option", text: /Executive DoA 2026/, count: 0
    assert_select "[draggable]", 0
    assert_select "[data-controller=inline-edit] form", 0
    assert_select "form[action=?]", dashboard_create_authority_path(matrix_id: @matrix.id), 0

    patch dashboard_update_authority_path(older, matrix_id: @matrix.id), params: { authority: { name_en: "Changed" } }
    assert_equal "Old", older.reload.name_en

    get dashboard_authorities_path(matrix_id: newest.id)
    assert_select "[data-controller=inline-edit] form"
  end

  test "the review round: send, everyone accepts, the admin publishes, and the version locks" do
    gov = create_user("doa-gov", CompanyUser::ROLES[:company_risk_manager])
    gov.company_user.update!(gov_manager: true)
    reviewer = create_user("doa-rev", CompanyUser::ROLES[:company_contributor])
    @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    sign_in gov
    post dashboard_send_authority_review_path(matrix_id: @matrix.id), params: { user_ids: [ reviewer.id ] }
    review = @matrix.matrix_reviews.sole
    assert review.pending?
    assert Notification.exists?(recipient: reviewer, kind: "authority_review_requested")
    post dashboard_publish_authority_matrix_path(matrix_id: @matrix.id)
    refute @matrix.reload.published?, "a Governance Manager does not publish"
    sign_out gov

    sign_in reviewer
    get dashboard_authorities_path(matrix_id: @matrix.id)
    assert_select "form[action=?]", dashboard_answer_authority_review_path(review, matrix_id: @matrix.id)
    patch dashboard_answer_authority_review_path(review, matrix_id: @matrix.id), params: { decision: "rejected", comment: "" }
    assert review.reload.pending?, "rejecting needs a reason"
    patch dashboard_answer_authority_review_path(review, matrix_id: @matrix.id), params: { decision: "accepted" }
    assert review.reload.accepted?
    sign_out reviewer

    sign_in @admin
    post dashboard_publish_authority_matrix_path(matrix_id: @matrix.id)
    @matrix.reload
    assert @matrix.published?
    assert @matrix.published_at.present?
    post dashboard_create_authority_path, params: { matrix_id: @matrix.id, authority: { name_en: "Too late" } }
    assert_equal 1, @matrix.authorities.count, "a published version is locked"
  end

  test "the matrix lists a level column per authority level" do
    sign_in @admin
    @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    get dashboard_authorities_path
    assert_response :success
    # One box per level under each band, rather than a column per level.
    AuthorityLevel::KEYS.each { |key| assert_select "p", text: AuthorityLevel.label(key) }
  end

  test "an authority can be added and appears under its category" do
    sign_in @admin
    post dashboard_create_authority_path, params: {
      matrix_id: @matrix.id,
      authority: { authority_category_id: @category.id, name_en: "Sign contracts" }
    }

    assert_redirected_to dashboard_authorities_path(matrix_id: @matrix.id)
    authority = @matrix.authorities.sole
    assert_equal 1, authority.number

    follow_redirect!
    assert_includes response.body, "Sign contracts"
    assert_includes response.body, "Contracting"
  end

  test "the findings report names an authority nobody may authorize" do
    @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    sign_in @admin
    get dashboard_authorities_path

    assert_includes response.body, I18n.t("doa.findings.no_authorizer")
    assert_select "details[data-authority-matrix-target=findings] summary.text-red-700", text: /#{I18n.t('doa.findings.title')}/
    assert_select "details[data-authority-matrix-target=findings][open]", 0, "findings start folded"
    assert_select "a[href=?]", "#authority-#{@matrix.authorities.sole.id}", text: I18n.t("doa.findings.fix")
  end

  test "an authority with a single authorizer raises no findings; a basis is not asked for" do
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)

    sign_in @admin
    get dashboard_authorities_path

    assert_response :success
    assert_not_includes response.body, I18n.t("doa.findings.title"), "the findings box is shown only when there is something to say"
  end

  test "a holder can be assigned by unit or by dynamic role" do
    authority = @company.authorities.create!(matrix: @matrix, authority_category: @category, name_en: "Sign contracts")

    sign_in @admin
    post dashboard_create_authority_assignment_path(authority_id: authority.id), params: {
      matrix_id: @matrix.id, holder: "unit:#{@minister.id}",
      authority_assignment: { level: "authorize" }
    }
    post dashboard_create_authority_assignment_path(authority_id: authority.id), params: {
      matrix_id: @matrix.id, holder: "role:owning_unit",
      authority_assignment: { level: "review", condition: "Where above SAR 1m" }
    }

    levels = authority.reload.assignments.map(&:level)
    assert_equal %w[authorize review], levels.sort.reverse.sort
    assert_equal "Where above SAR 1m", authority.assignments.find_by(level: "review").condition
  end


  test "a viewer can read the matrix but not change it" do
    sign_in @viewer
    get dashboard_authorities_path
    assert_response :success

    post dashboard_create_authority_path, params: {
      matrix_id: @matrix.id, authority: { name_en: "Sneak" }
    }
    assert_redirected_to dashboard_authorities_path
    assert_equal 0, @matrix.authorities.count
  end

  test "opening the next version copies the matrix and shows no changes yet" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)

    sign_in @admin
    post dashboard_open_next_authority_version_path(matrix_id: @matrix.id)

    successor = @company.pp_records.of_type("executive_doa").order(:version_number).last
    assert_equal 2, successor.version_number
    assert_redirected_to dashboard_authorities_path(matrix_id: successor.id)

    follow_redirect!
    assert_includes response.body, I18n.t("doa.diff.none")
  end

  test "a change to the new version is reported against the previous one" do
    @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    successor = AuthorityMatrixVersionService.open_next(@matrix.reload)
    successor.authorities.sole.update!(name_en: "Sign contracts and agreements")

    sign_in @admin
    get dashboard_authorities_path(matrix_id: successor.id)

    assert_includes response.body, I18n.t("doa.diff.amended")
    assert_includes response.body, I18n.t("doa.diff.aspects.name")
  end

  test "a reviewer comments on an authority and the owner answers with a reason" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    reviewer = create_user("doa-reviewer", CompanyUser::ROLES[:company_quality_manager])
    @matrix.matrix_reviews.create!(user: reviewer, requested_by: @admin, requested_at: Time.current)

    sign_in reviewer
    post dashboard_create_authority_review_comment_path(authority_id: authority.id, matrix_id: @matrix.id),
      params: { body: "Approval sits with the wrong deputy" }
    comment = @matrix.review_comments.sole
    assert_equal reviewer, comment.user
    assert_not comment.answered?

    get dashboard_authorities_path
    assert_includes response.body, "Approval sits with the wrong deputy"
    assert_includes response.body, I18n.t("doa.comments.waiting")

    sign_in @admin
    patch dashboard_answer_authority_review_comment_path(comment, matrix_id: @matrix.id),
      params: { decision: "rejected", reply: "" }
    assert_not comment.reload.answered?, "an answer needs a reason"

    patch dashboard_answer_authority_review_comment_path(comment, matrix_id: @matrix.id),
      params: { decision: "accepted", reply: "Moved to the concerned agency." }
    comment.reload
    assert_equal [ "accepted", @admin ], [ comment.decision, comment.replied_by ]
    assert_not_nil comment.replied_at
  end

  test "someone who is not a reviewer or owner cannot comment, and the consultation box is gone" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    sign_in @viewer
    post dashboard_create_authority_review_comment_path(authority_id: authority.id, matrix_id: @matrix.id), params: { body: "x" }
    assert_equal 0, @matrix.review_comments.count

    get dashboard_authorities_path
    assert_not_includes response.body, "Raise an objection"
  end

  test "the Excel template lists units and people as dropdown choices and the filled sheet imports" do
    unit = @company.org_units.create!(name_en: "Procurement", level: 1)
    sign_in @admin

    get dashboard_authorities_template_path(matrix_id: @matrix.id)
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    book = Roo::Excelx.new(StringIO.new(response.body), file_warning: :ignore)
    assert_equal [ "Authorities", "Lists", "How to fill" ], book.sheets
    lists = book.sheet("Lists")
    assert_includes lists.column(1), "Unit: Procurement"
    assert_includes lists.column(2), "Person: #{@admin.name}"
    assert_includes lists.column(3), "Role: The owning unit"

    file = Tempfile.new([ "authorities", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Authorities") do |sheet|
        sheet.add_row AuthorityImportTemplate::HEADERS
        sheet.add_row [ "Contracting", "Sign contracts", "توقيع العقود", "Unit: Procurement", nil, nil, nil, "Unit: Minister", "Person: #{@admin.name}" ]
        sheet.add_row [ "Finance", "Approve budgets", nil, nil, nil, nil, "Role: The owning unit", "Unit: Minister | Unit: Procurement", nil ]
      end
      p.serialize(file.path)
    end

    post dashboard_import_authorities_path(matrix_id: @matrix.id),
      params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    assert_redirected_to dashboard_authorities_path(matrix_id: @matrix.id)

    assert_equal 2, @matrix.authorities.count
    contracts = @matrix.authorities.find_by(name_en: "Sign contracts")
    assert_equal @category, contracts.authority_category
    assert_equal "توقيع العقود", contracts.name_ar
    holders = contracts.default_band.assignments
    assert_equal [ unit.id ], holders.select { |a| a.level == "prepare" }.map(&:org_unit_id)
    assert_equal [ @minister.id ], holders.select { |a| a.level == "authorize" }.map(&:org_unit_id)
    assert_equal [ @admin.id ], holders.select { |a| a.level == "inform" }.map(&:user_id)

    budgets = @matrix.authorities.find_by(name_en: "Approve budgets")
    assert_equal "Finance", budgets.authority_category.name_en
    assert_equal [ "owning_unit" ], budgets.default_band.assignments.select { |a| a.level == "recommend" }.map(&:dynamic_role)
    assert_equal 2, budgets.default_band.assignments.count { |a| a.level == "authorize" }
  end

  test "an import with an unknown holder saves nothing and names the row" do
    file = Tempfile.new([ "authorities", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Authorities") do |sheet|
        sheet.add_row AuthorityImportTemplate::HEADERS
        sheet.add_row [ "Contracting", "Sign contracts", nil, nil, nil, nil, nil, "Unit: Minister", nil ]
        sheet.add_row [ "Contracting", "Sign NDAs", nil, nil, nil, nil, nil, "Nobody Here", nil ]
      end
      p.serialize(file.path)
    end

    sign_in @admin
    post dashboard_import_authorities_path(matrix_id: @matrix.id),
      params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("doa.import.row", number: 3)
    assert_equal 0, @matrix.authorities.count
  end

  test "a delegation can be recorded and shows as in force" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)

    sign_in @admin
    post dashboard_create_authority_delegation_path(matrix_id: @matrix.id), params: {
      authority_delegation: { authority_id: authority.id, from_org_unit_id: @minister.id,
                              to_org_unit_id: deputy.id, kind: "temporary", status: "active",
                              valid_from: Date.current.to_s, valid_to: (Date.current + 14).to_s }
    }

    delegation = @company.authority_delegations.sole
    assert delegation.in_force?

    # Ending inside the warning window, it is flagged before it lapses rather
    # than simply reported as in force.
    assert delegation.expiring_soon?
    follow_redirect!
    assert_includes response.body,
      I18n.t("doa.delegation.expiring", days: AuthorityDelegation::EXPIRY_LEAD_DAYS)
  end

  test "a delegation beyond what the holder may decide is refused" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    authority.bands.sole.update!(max_amount: 1_000_000)
    authority.bands.sole.assignments.create!(level: "authorize", org_unit: @minister)
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)

    sign_in @admin
    post dashboard_create_authority_delegation_path(matrix_id: @matrix.id), params: {
      authority_delegation: { authority_id: authority.id, from_org_unit_id: @minister.id,
                              to_org_unit_id: deputy.id, kind: "permanent", status: "active",
                              limit_amount: 9_000_000 }
    }

    assert_equal 0, @company.authority_delegations.count
    assert_includes flash[:alert], "1000000"
  end

  test "revoking a delegation records who did it and why" do
    authority = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    delegation = @company.authority_delegations.create!(authority: authority, from_org_unit: @minister,
      to_org_unit: deputy, kind: "permanent", status: "active")

    sign_in @admin
    patch dashboard_revoke_authority_delegation_path(delegation, matrix_id: @matrix.id), params: {
      authority_delegation: { revocation_reason: "The postholder returned." }
    }

    delegation.reload
    assert delegation.revoked?
    assert_equal @admin, delegation.revoked_by
    assert_not delegation.in_force?
  end

  test "suggestions are offered but nothing is created until asked for" do
    sign_in @admin
    get dashboard_authorities_path

    assert_response :success
    # assert_select decodes entities; the note contains an apostrophe.
    assert_select "h2", text: I18n.t("doa.catalogue.title")
    assert_equal 0, @matrix.authorities.count, "suggestions must not create anything by being shown"
  end

  test "chosen suggestions become the company's own records" do
    sign_in @admin
    post dashboard_apply_authority_suggestions_path(matrix_id: @matrix.id),
      params: { category_keys: %w[financial] }

    assert_redirected_to dashboard_authorities_path(matrix_id: @matrix.id)
    assert_operator @matrix.reload.authorities.count, :>, 0
    assert @matrix.authorities.all? { |a| a.assignments.empty? }, "no holder is ever suggested"
  end

  test "applying with nothing selected says so rather than silently doing nothing" do
    sign_in @admin
    post dashboard_apply_authority_suggestions_path(matrix_id: @matrix.id), params: {}

    assert_equal 0, @matrix.authorities.count
    assert_includes flash[:alert], I18n.t("doa.catalogue.none_selected")
  end

  test "a viewer is not offered suggestions" do
    sign_in @viewer
    get dashboard_authorities_path

    assert_response :success
    assert_not_includes response.body, I18n.t("doa.catalogue.apply")
  end

  test "another company's matrix is not reachable" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "executive_doa", title_en: "Foreign DoA")

    sign_in @admin
    get dashboard_authorities_path(matrix_id: foreign.id)

    assert_response :success
    assert_not_includes response.body, "Foreign DoA"
  end
end
