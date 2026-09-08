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
    due = AuthorityDelegation
      .active_status
      .where(expiry_notified_at: nil)
      .where(valid_to: Date.current..AuthorityDelegation::EXPIRY_LEAD_DAYS.days.from_now.to_date)
      .includes(:authority, :from_org_unit, :to_org_unit, company: [])

    due.find_each { |delegation| notify(delegation) }
  end

  private

  def notify(delegation)
    recipients = recipients_for(delegation)

    # Stamped even when nobody can be told, or the job would retry this
    # delegation every run for the rest of its life.
    if recipients.empty?
      delegation.update_columns(expiry_notified_at: Time.current)
      return
    end

    recipients.each { |user| create_notification(delegation, user) }
    delegation.update_columns(expiry_notified_at: Time.current)
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
