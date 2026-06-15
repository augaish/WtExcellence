require 'faker'

puts "Creating languages..."
Language.find_or_create_by!(code: 'en') do |lang|
  lang.name = 'English'
  lang.direction = 'ltr'
end

Language.find_or_create_by!(code: 'ar') do |lang|
  lang.name = 'العربية'
  lang.direction = 'rtl'
end
puts "Languages created!"
puts ""

puts "Creating users..."
super_admin = User.find_or_create_by!(email: 'superadmin@example.com') do |user|
  user.name = 'Super Admin'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = 'super_admin'
  user.is_active = true
  user.locale_code = 'en'
end
puts "  Created Super Admin: #{super_admin.email} (password: password123)"

regular_user1 = User.find_or_create_by!(email: 'user1@example.com') do |user|
  user.name = 'Regular User 1'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'en'
end
puts "  Created Regular User 1: #{regular_user1.email} (password: password123)"

regular_user2 = User.find_or_create_by!(email: 'user2@example.com') do |user|
  user.name = 'Regular User 2'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'ar'
end
puts "  Created Regular User 2: #{regular_user2.email} (password: password123)"

regular_user3 = User.find_or_create_by!(email: 'user3@example.com') do |user|
  user.name = 'Regular User 3'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'en'
end
puts "  Created Regular User 3: #{regular_user3.email} (password: password123)"

regular_user4 = User.find_or_create_by!(email: 'user4@example.com') do |user|
  user.name = 'Regular User 4'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'en'
end
puts "  Created Regular User 4: #{regular_user4.email} (password: password123)"

regular_user5 = User.find_or_create_by!(email: 'user5@example.com') do |user|
  user.name = 'Regular User 5'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'ar'
end
puts "  Created Regular User 5: #{regular_user5.email} (password: password123)"

quality_manager = User.find_or_create_by!(email: 'qm@example.com') do |user|
  user.name = 'Quality Manager'
  user.password = 'password123'
  user.password_confirmation = 'password123'
  user.role = nil
  user.is_active = true
  user.locale_code = 'en'
end
puts "  Created Quality Manager: #{quality_manager.email} (password: password123)"
puts "Users created!"
puts ""

puts "Creating companies..."
company1 = Company.find_or_create_by!(name: 'Acme Corporation') do |company|
  company.license_seats = 50
  company.is_active = true
  company.default_locale = 'en'
end
puts "  Created Company 1: #{company1.name}"

company2 = Company.find_or_create_by!(name: 'Tech Solutions Inc') do |company|
  company.license_seats = 30
  company.is_active = true
  company.default_locale = 'ar'
end
puts "  Created Company 2: #{company2.name}"
puts "Companies created!"
puts ""

puts "Creating company users..."
CompanyUser.find_or_create_by!(company: company1, user: regular_user1) do |cu|
  cu.role = 'company_admin'
end
puts "  Company 1 - #{regular_user1.name} as company_admin"

CompanyUser.find_or_create_by!(company: company1, user: regular_user2) do |cu|
  cu.role = 'company_auditor'
end
puts "  Company 1 - #{regular_user2.name} as company_auditor"

CompanyUser.find_or_create_by!(company: company1, user: regular_user3) do |cu|
  cu.role = 'company_contributor'
end
puts "  Company 1 - #{regular_user3.name} as company_contributor"

CompanyUser.find_or_create_by!(company: company1, user: regular_user4) do |cu|
  cu.role = 'company_viewer'
end
puts "  Company 1 - #{regular_user4.name} as company_viewer"

CompanyUser.find_or_create_by!(company: company1, user: quality_manager) do |cu|
  cu.role = 'company_quality_manager'
end
puts "  Company 1 - #{quality_manager.name} as company_quality_manager"

CompanyUser.find_or_create_by!(company: company2, user: regular_user5) do |cu|
  cu.role = 'company_admin'
end
puts "  Company 2 - #{regular_user5.name} as company_admin"
puts "Company users created!"
puts ""

puts "Creating CAPAs..."
# Get company users for assignments
company1_admin = CompanyUser.find_by(company: company1, user: regular_user1)
company1_auditor = CompanyUser.find_by(company: company1, user: regular_user2)
company1_contributor = CompanyUser.find_by(company: company1, user: regular_user3)
company2_admin = CompanyUser.find_by(company: company2, user: regular_user5)

# Company 1 CAPAs
capa1 = Capa.find_or_create_by!(title: 'Non-conformance in Production Line A', company: company1) do |c|
  c.description = 'Quality control inspection revealed deviations from standard operating procedures in Production Line A. Multiple batches affected.'
  c.source = 'internal_audit'
  c.priority = 'high'
  c.status = 'open'
  c.due_date = 30.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa1, company_user: company1_admin)
capa1.reload
capa1.sync_status_with_assignments
puts "  Company 1 - Created CAPA: #{capa1.title} (assigned to #{regular_user1.name})"

capa2 = Capa.find_or_create_by!(title: 'Customer Complaint: Product Defect', company: company1) do |c|
  c.description = 'Customer reported defective products in recent shipment. Investigation required to identify root cause and prevent recurrence.'
  c.source = 'customer_complaint'
  c.priority = 'high'
  c.status = 'in_progress'
  c.due_date = 14.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa2, company_user: company1_auditor)
capa2.reload
capa2.sync_status_with_assignments
puts "  Company 1 - Created CAPA: #{capa2.title} (assigned to #{regular_user2.name})"

capa3 = Capa.find_or_create_by!(title: 'External Audit Finding: Documentation Gap', company: company1) do |c|
  c.description = 'External audit identified gaps in quality management documentation. Need to update procedures and training materials.'
  c.source = 'external_audit'
  c.priority = 'medium'
  c.status = 'in_progress'
  c.due_date = 45.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa3, company_user: company1_contributor)
capa3.reload
capa3.sync_status_with_assignments
puts "  Company 1 - Created CAPA: #{capa3.title} (assigned to #{regular_user3.name})"

capa4 = Capa.find_or_create_by!(title: 'Process Improvement Opportunity', company: company1) do |c|
  c.description = 'Internal review identified opportunity to streamline workflow processes and reduce waste in manufacturing operations.'
  c.source = 'internal_audit'
  c.priority = 'low'
  c.status = 'open'
  c.due_date = 60.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa4, company_user: company1_admin)
capa4.reload
capa4.sync_status_with_assignments
puts "  Company 1 - Created CAPA: #{capa4.title} (assigned to #{regular_user1.name})"

capa5 = Capa.find_or_create_by!(title: 'Supplier Quality Issue', company: company1) do |c|
  c.description = 'Received non-conforming materials from supplier. Need to address supplier quality management and establish corrective measures.'
  c.source = 'external_audit'
  c.priority = 'medium'
  c.status = 'closed'
  c.due_date = 20.days.ago
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa5, company_user: company1_admin)
capa5.reload
capa5.sync_status_with_assignments
puts "  Company 1 - Created CAPA: #{capa5.title} (assigned to #{regular_user1.name})"

# Company 2 CAPAs
capa6 = Capa.find_or_create_by!(title: 'Software Bug in Production System', company: company2) do |c|
  c.description = 'Critical bug discovered in production system affecting customer data processing. Immediate action required to resolve and prevent data loss.'
  c.source = 'customer_complaint'
  c.priority = 'high'
  c.status = 'in_progress'
  c.due_date = 7.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa6, company_user: company2_admin)
capa6.reload
capa6.sync_status_with_assignments
puts "  Company 2 - Created CAPA: #{capa6.title} (assigned to #{regular_user5.name})"

capa7 = Capa.find_or_create_by!(title: 'Security Audit Finding', company: company2) do |c|
  c.description = 'Security audit identified vulnerabilities in access control system. Need to implement enhanced security measures and update policies.'
  c.source = 'external_audit'
  c.priority = 'high'
  c.status = 'open'
  c.due_date = 21.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa7, company_user: company2_admin)
capa7.reload
capa7.sync_status_with_assignments
puts "  Company 2 - Created CAPA: #{capa7.title} (assigned to #{regular_user5.name})"

capa8 = Capa.find_or_create_by!(title: 'Performance Optimization', company: company2) do |c|
  c.description = 'Internal analysis shows system performance degradation. Optimization needed to improve response times and user experience.'
  c.source = 'internal_audit'
  c.priority = 'medium'
  c.status = 'in_progress'
  c.due_date = 35.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa8, company_user: company2_admin)
capa8.reload
capa8.sync_status_with_assignments
puts "  Company 2 - Created CAPA: #{capa8.title} (assigned to #{regular_user5.name})"

capa9 = Capa.find_or_create_by!(title: 'Documentation Update Required', company: company2) do |c|
  c.description = 'Technical documentation needs updating to reflect recent system changes and new features. Documentation review and update process needed.'
  c.source = 'internal_audit'
  c.priority = 'low'
  c.status = 'open'
  c.due_date = 90.days.from_now
  c.archived = false
end
CapaAssignment.find_or_create_by!(capa: capa9, company_user: company2_admin)
capa9.reload
capa9.sync_status_with_assignments
puts "  Company 2 - Created CAPA: #{capa9.title} (assigned to #{regular_user5.name})"
puts "CAPAs created!"
puts ""

puts "Creating AI action credits..."
AiActionCredit.find_or_create_by!(action_type: 'GENERATE_CAPA_ACTIONS') do |credit|
  credit.credit_cost = 5
  credit.display_name = 'Generate Actions'
end
puts "  Created: GENERATE_CAPA_ACTIONS (5 credits)"

AiActionCredit.find_or_create_by!(action_type: 'GENERATE_CAPA_QUESTIONNAIRE') do |credit|
  credit.credit_cost = 0
  credit.display_name = 'Generate Questionnaire'
end
puts "  Created: GENERATE_CAPA_QUESTIONNAIRE (0 credits)"

AiActionCredit.find_or_create_by!(action_type: 'SUGGEST_CAPA_CLAUSES') do |credit|
  credit.credit_cost = 7
  credit.display_name = 'Suggest Clauses'
end
puts "  Created: SUGGEST_CAPA_CLAUSES (7 credits)"

AiActionCredit.find_or_create_by!(action_type: 'REGENERATE_ROOT_CAUSE') do |credit|
  credit.credit_cost = 0
  credit.display_name = 'Regenerate Root Cause'
end
puts "  Created: REGENERATE_ROOT_CAUSE (0 credits)"
puts "AI action credits created!"
puts ""

puts "Seed data created successfully!"
