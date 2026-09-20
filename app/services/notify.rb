# One door for in-app notices. Every movement in the product that concerns a
# person other than the one acting goes through here: the title is written in
# the recipient's language, the actor never notifies themself, and the same
# person is told once per call. Email follows the recipient's own setting
# (see Notification#deliver_email).
#
#   Notify.people(recipients, kind: "record_returned", source: record,
#     link_path: path, actor: current_user, title: "…", reason: "…")
module Notify
  module_function

  def people(recipients, kind:, source:, link_path:, actor: nil, **title_args)
    Array(recipients).compact.uniq.reject { |r| actor && r.id == actor.id }.map do |recipient|
      person(recipient, kind: kind, source: source, link_path: link_path, actor: actor, **title_args)
    end.compact
  end

  def person(recipient, kind:, source:, link_path:, actor: nil, **title_args)
    return nil if recipient.nil? || (actor && recipient.id == actor.id)

    locale = recipient.try(:locale).presence || recipient.try(:locale_code).presence || I18n.default_locale
    args = title_args.merge(actor_name: actor&.name.to_s)
    Notification.create!(
      recipient: recipient, source: source, kind: kind, link_path: link_path,
      title: I18n.t("user_notifications.#{kind}_title", locale: locale, **args),
      payload: args.merge(actor_id: actor&.id)
    )
  rescue => e
    Rails.logger.warn "Notification #{kind} failed: #{e.class}: #{e.message}"
    nil
  end
end
