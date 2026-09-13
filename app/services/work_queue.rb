# What needs this person now, across every module, so the overview answers
# "what needs my action?" before it shows a single chart. Each item names the
# record, why it is here, and where to go. Nothing here is a report; it is a
# to-do list drawn from the same rules the modules enforce.
class WorkQueue
  Item = Struct.new(:kind, :title, :reason, :path, :due_on, keyword_init: true)

  def initialize(user:, company:)
    @user = user
    @company = company
    @membership = user&.company_user
    @routes = Rails.application.routes.url_helpers
  end

  def items
    @items ||= (documenter + capa_actions + risks + controls + commitments + vendors + authority_reviews)
      .sort_by { |i| [ i.due_on || Date.new(9999), i.title ] }
  end

  def empty?
    items.empty?
  end

  def count
    items.size
  end

  private

  attr_reader :user, :company, :membership, :routes

  def documenter
    return [] if user.nil? || !company.module_enabled?(:pp)

    DocumenterInbox.new(user: user, company: company).items.map do |inbox|
      Item.new(kind: :documenter, title: inbox.record.display_title,
        reason: I18n.t("documenter.inbox.reasons.#{inbox.reason}"), path: routes.dashboard_documenter_record_path(inbox.record), due_on: nil)
    end
  end

  # The actions handed to me that are open, overdue first.
  def capa_actions
    return [] if membership.nil? || !company.module_enabled?(:capa)

    CapaAction.joins(:capa_action_assignments, :capa)
      .where(capa_action_assignments: { company_user_id: membership.id })
      .where(capas: { company_id: company.id, archived: false })
      .where.not(status: %w[done proposed]).includes(:capa).map do |action|
        overdue = action.due_date.present? && action.due_date < Date.current
        Item.new(kind: :capa_action, title: action.title,
          reason: overdue ? I18n.t("work_queue.reasons.action_overdue", days: (Date.current - action.due_date).to_i) : I18n.t("work_queue.reasons.action_open"),
          path: routes.dashboard_capa_action_show_path(action.capa_id, action.id), due_on: action.due_date)
      end
  end

  # Risks I own that need a decision: acceptance above appetite, or a review.
  def risks
    return [] if membership.nil? || !company.module_enabled?(:risk)

    Risk.active.where(company_id: company.id, owner_id: membership.id).where.not(status: "closed").filter_map do |risk|
      if risk.needs_acceptance?
        Item.new(kind: :risk, title: risk.title, reason: I18n.t("work_queue.reasons.risk_needs_acceptance"),
          path: routes.dashboard_risk_management_path(risk), due_on: risk.next_review_on)
      elsif risk.review_overdue?
        Item.new(kind: :risk, title: risk.title, reason: I18n.t("work_queue.reasons.review_overdue"),
          path: routes.dashboard_risk_management_path(risk), due_on: risk.next_review_on)
      end
    end
  end

  # A person without the governance licence is sent to the scoped task page,
  # never to a register they cannot open.
  def commitments
    return [] if membership.nil? || !company.module_enabled?(:commitments)

    CustomerCommitment.active.where(company_id: company.id, owner_id: membership.id).where.not(status: "fulfilled").filter_map do |c|
      next unless c.past_due? || c.timing_state == "due_soon" || !governance_reader?

      path = governance_reader? ? routes.dashboard_customer_commitment_path(c) : routes.dashboard_commitment_task_path(c)
      Item.new(kind: :commitment, title: c.title, reason: c.timing_label, path: path, due_on: c.due_date)
    end
  end

  # The control owner's own item: report on the control until it is submitted.
  def controls
    return [] if membership.nil? || !company.module_enabled?(:risk)

    Risk.active.where(company_id: company.id, control_owner_id: membership.id, control_evidence_submitted_at: nil)
        .where.not(status: "closed").map do |risk|
      Item.new(kind: :risk, title: risk.title, reason: I18n.t("work_queue.reasons.control_evidence_due"),
        path: routes.dashboard_control_task_path(risk), due_on: risk.next_review_on)
    end
  end

  def governance_reader?
    user.can_view_governance?
  end

  def vendors
    return [] if membership.nil? || !company.module_enabled?(:vendors)

    Vendor.active.where(company_id: company.id, owner_id: membership.id).review_overdue.map do |v|
      Item.new(kind: :vendor, title: v.name, reason: I18n.t("work_queue.reasons.review_overdue"),
        path: routes.dashboard_vendor_path(v), due_on: v.next_review_on)
    end
  end

  def authority_reviews
    return [] if user.nil? || !company.module_enabled?(:authorities)

    AuthorityMatrixReview.pending.where(user_id: user.id).joins(:matrix).where(pp_records: { company_id: company.id }).includes(:matrix).map do |review|
      Item.new(kind: :authority_review, title: review.matrix.display_title, reason: I18n.t("work_queue.reasons.authority_review"),
        path: routes.dashboard_authorities_path(matrix_id: review.matrix_id), due_on: nil)
    end
  end
end
