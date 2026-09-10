require "roo"

# Invites a company's users from the filled-in template.
#
#   result = UserImportService.import(file: uploaded_file, company: company, actor: current_user)
#   result.invited / result.errors  # => [{ row:, message: }]
#
# Every row is checked first — name, a valid email nobody has yet, a known
# role, a known unit when given, and no more rows than free seats — and the
# whole file is refused when any row fails. The users are then created the
# way "Add user" creates one: inactive, with an invitation that lets them set
# their own password. The emails go out once the transaction has committed.
class UserImportService
  Result = Struct.new(:invited, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.import(file:, company:, actor:)
    new(file: file, company: company, actor: actor).import
  end

  def initialize(file:, company:, actor:)
    @file = file
    @company = company
    @actor = actor
    @template = UserImportTemplate.new(company)
    @errors = []
  end

  def import
    rows = read_rows
    return failure if @errors.any?
    return fail_with(0, I18n.t("user_import.empty")) if rows.empty?

    free = @template.free_seats
    return fail_with(0, I18n.t("user_import.too_many_rows", rows: rows.size, free: free)) if rows.size > free

    prepared = rows.map { |row| prepare(row) }
    return failure if @errors.any?

    users = []
    ActiveRecord::Base.transaction do
      users = prepared.map { |attributes| invite(attributes) }
    end
    users.each { |user| deliver(user) }

    Result.new(invited: users.size, errors: [])
  end

  private

  def failure
    Result.new(invited: 0, errors: @errors)
  end

  def fail_with(row, message)
    @errors << { row: row, message: message }
    failure
  end

  # The header sits on row 2, under the seats line; a sheet without that
  # line (a hand-made file) is read from row 1.
  def read_rows
    sheet = Roo::Spreadsheet.open(@file.path, extension: extension)
    sheet = sheet.sheet("Users") if sheet.respond_to?(:sheets) && sheet.sheets.include?("Users")
    header_row = (1..2).find { |i| header_keys(sheet.row(i)).include?("email") }
    return @errors << { row: 0, message: I18n.t("user_import.no_header") } if header_row.nil?

    header = header_keys(sheet.row(header_row))
    rows = []
    ((header_row + 1)..sheet.last_row.to_i).each do |i|
      values = sheet.row(i)
      next if values.all? { |v| v.to_s.strip.empty? }

      rows << { number: i, data: header.zip(values).to_h }
    end
    rows
  rescue => e
    @errors << { row: 0, message: I18n.t("user_import.unreadable", error: e.message) }
    []
  end

  def header_keys(cells)
    cells.map do |cell|
      text = cell.to_s.strip.downcase
      UserImportTemplate::HEADERS.find do |key|
        key == text || I18n.available_locales.any? { |l| I18n.t("user_import.columns.#{key}", locale: l).downcase == text }
      end || text
    end
  end

  def extension
    ext = File.extname(@file.original_filename.to_s).delete(".").downcase
    ext.presence&.to_sym || :xlsx
  end

  def prepare(row)
    d = row[:data]
    name = d["name"].to_s.strip
    email = d["email"].to_s.strip.downcase
    role = resolve_role(d["role"])
    unit = resolve_unit(d["org_unit"])

    @errors << { row: row[:number], message: I18n.t("user_import.name_required") } if name.blank?
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      @errors << { row: row[:number], message: I18n.t("user_import.email_invalid", email: email) }
    elsif User.exists?(email: email)
      @errors << { row: row[:number], message: I18n.t("user_import.email_taken", email: email) }
    elsif (@seen ||= {})[email]
      @errors << { row: row[:number], message: I18n.t("user_import.email_repeated", email: email, other: @seen[email]) }
    end
    @seen[email] ||= row[:number] if email.present?
    @errors << { row: row[:number], message: I18n.t("user_import.role_unknown", role: d["role"]) } if role.nil?
    @errors << { row: row[:number], message: I18n.t("user_import.unit_unknown", unit: d["org_unit"]) } if unit == :unknown

    { name: name, email: email, role: role, org_unit: (unit == :unknown ? nil : unit) }
  end

  def resolve_role(value)
    text = value.to_s.strip
    return nil if text.blank?

    CompanyUser::ROLES.values.find do |role|
      role == text.downcase || I18n.available_locales.any? { |l| I18n.t("user_import.roles.#{role}", locale: l).casecmp?(text) }
    end
  end

  def resolve_unit(value)
    text = value.to_s.strip
    return nil if text.blank?

    @company.org_units.detect { |u| [ u.name_en, u.name_ar, u.code ].compact.any? { |n| n.casecmp?(text) } } || :unknown
  end

  # Mirrors AccountManagementController#create_invitation for one person.
  def invite(attributes)
    temporary_password = SecureRandom.urlsafe_base64(32)
    user = User.create!(
      name: attributes[:name],
      email: attributes[:email],
      org_unit: attributes[:org_unit],
      password: temporary_password,
      password_confirmation: temporary_password,
      invitation_token: User.generate_invitation_token,
      invitation_sent_at: Time.current,
      invitation_expires_at: 7.days.from_now,
      invited_by: @actor,
      is_active: false
    )
    CompanyUser.create!(company: @company, user: user, role: attributes[:role])
    AuditLogService.log_action(actor_user: @actor, company: @company, action: "CREATE_USER_INVITATION",
      entity_type: "user", entity_id: user.id,
      payload: { user_id: user.id, user_name: user.name, user_email: user.email, company_id: @company.id,
                 company_name: @company.name, company_role: attributes[:role], source: "excel_import" })
    user
  end

  def deliver(user)
    mail = UserInvitationMailer.invitation_email(user, @company)
    Rails.env.development? ? mail.deliver_now : mail.deliver_later
  end
end
