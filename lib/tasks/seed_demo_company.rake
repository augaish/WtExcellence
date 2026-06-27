namespace :demo do
  desc "Create a demo company with users for each role (admin, quality manager, auditor, contributor, viewer)"
  task seed_company: :environment do
    password = ENV.fetch("DEMO_PASSWORD", "Password1!")
    company_name = ENV.fetch("DEMO_COMPANY", "Acme Excellence Co.")
    domain = ENV.fetch("DEMO_EMAIL_DOMAIN", "demo.wtexcel.com")

    users_spec = [
      { role: "company_admin",           name: "Alice Admin",      email_local: "admin" },
      { role: "company_quality_manager", name: "Quinn Quality",    email_local: "qm" },
      { role: "company_auditor",         name: "Avery Auditor",    email_local: "auditor" },
      { role: "company_contributor",     name: "Chris Contributor", email_local: "contributor1" },
      { role: "company_contributor",     name: "Casey Contributor", email_local: "contributor2" },
      { role: "company_viewer",          name: "Vera Viewer",      email_local: "viewer" }
    ]

    ActiveRecord::Base.transaction do
      company = Company.find_or_initialize_by(name: company_name)
      company.license_seats ||= 25
      company.credits ||= 1000
      company.is_active = true
      company.status = "active"
      company.default_locale ||= "en"
      company.save!

      puts "Company: #{company.name} (#{company.id})"

      users_spec.each do |spec|
        email = "#{spec[:email_local]}@#{domain}"

        user = User.find_or_initialize_by(email: email)
        user.name = spec[:name]
        user.password = password
        user.password_confirmation = password
        user.is_active = true
        user.status = "active"
        user.locale_code ||= "en"
        user.invitation_accepted_at ||= Time.current
        user.save!

        company_user = CompanyUser.find_or_initialize_by(company: company, user: user)
        company_user.role = spec[:role]
        company_user.save!

        puts "  - #{spec[:role].ljust(26)} #{email} (password: #{password})"
      end
    end

    puts "\nDone. Sign in with any of the emails above using password: #{password}"
  end
end
