# Warns before a delegation lapses.
#
# A temporary delegation stops conferring authority the day after it ends, which
# is correct but silent: without this, the first anyone knows is that a decision
# can no longer be made. The matrix already shows the warning; this reaches the
# people who would otherwise have to go looking for it.
#
# Each delegation is warned about once. The stamp is what makes that true across
# restarts, rather than the job remembering.
class DelegationExpiryNoticeJob < ApplicationJob
  queue_as :cron_small

  def perform
    window = Date.current..AuthorityDelegation::EXPIRY_LEAD_DAYS.days.from_now.to_date

    # Never examined, or examined when there was nobody to tell. The second
    # group is looked at again in case a head has since been assigned.
    due = AuthorityDelegation
      .active_status
      .where(valid_to: window)
      .where("expiry_notified_at IS NULL OR expiry_notice_outcome = ?", "no_recipients")
      .includes(:authority, :from_org_unit, :to_org_unit, company: [])

    due.find_each { |delegation| notify(delegation) }
  end

  private

  def notify(delegation)
    recipients = recipients_for(delegation)

    # A headless delegation is stamped with that outcome rather than left
    # looking delivered, and is only re-examined once a head exists — so it is
    # neither retried every run nor silently unowned forever.
    if recipients.empty?
      delegation.update_columns(expiry_notified_at: Time.current, expiry_notice_outcome: "no_recipients")
      return
    end

    # Already delivered for this lapse; a re-examination adds nothing.
    return if delegation.expiry_notice_outcome == "delivered"

    recipients.each { |user| create_notification(delegation, user) }
    delegation.update_columns(expiry_notified_at: Time.current, expiry_notice_outcome: "delivered")
  rescue => e
    # One unnotifiable delegation must not stop the rest being warned about.
    Rails.logger.error "DelegationExpiryNoticeJob failed for #{delegation.id}: #{e.class}: #{e.message}"
  end

  # The heads of both positions: the one lending the authority and the one
  # exercising it. Both need to know, for different reasons.
  def recipients_for(delegation)
    [ delegation.from_org_unit&.head_user, delegation.to_org_unit&.head_user ].compact.uniq
  end

  def create_notification(delegation, user)
    Notification.create!(
      recipient: user,
      kind: "delegation_expiring",
      title: I18n.t("doa.delegation.notice.title",
        authority: delegation.authority.display_name),
      body: I18n.t("doa.delegation.notice.body",
        authority: delegation.authority.display_name,
        to: delegation.to_org_unit&.display_name,
        date: I18n.l(delegation.valid_to, format: :long)),
      link_path: "/dashboard/authorities",
      source: delegation
    )
  end
end
