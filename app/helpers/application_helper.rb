module ApplicationHelper
  # Pagy pagination support
  include Pagy::Frontend

  # Get current locale
  def current_locale
    I18n.locale
  end

  # Check if current locale is RTL
  def rtl?
    I18n.locale == :ar
  end

  # Get text direction
  def text_direction
    rtl? ? "rtl" : "ltr"
  end

  # Shared UI button vocabulary for consistent affordances across the dashboard.
  # Includes accessible focus-visible rings (ui-ux-pro-max) and a subtle press
  # feedback (emil-design-eng) at product-appropriate 150ms.
  UI_BTN_BASE = "inline-flex items-center justify-center gap-2 px-4 h-10 rounded-lg text-sm font-semibold " \
                "transition-[transform,background-color,border-color] duration-150 active:scale-[0.98] " \
                "focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-[#5C3984]".freeze

  def ui_btn_primary
    "#{UI_BTN_BASE} text-white bg-[#5C3984] hover:bg-[#4A2F6B]"
  end

  def ui_btn_secondary
    "#{UI_BTN_BASE} text-[#5C3984] border border-[#5C3984] hover:bg-[#F6EEFF]"
  end

  def ui_btn_neutral
    "#{UI_BTN_BASE} text-gray-700 border border-gray-300 hover:bg-gray-50"
  end

  def ui_btn_danger
    "#{UI_BTN_BASE} text-red-600 border border-red-300 hover:bg-red-50"
  end

  # Consistent form-field vocabulary.
  def ui_label
    "block text-sm font-medium text-gray-700 mb-1.5"
  end

  # Padding-based height so it's safe for text inputs, selects, and textareas.
  def ui_input
    "w-full px-4 py-3 border border-gray-300 rounded-lg text-sm text-[#0D1120] " \
    "focus:outline-none focus:ring-2 focus:ring-[#5C3984] focus:border-transparent transition-shadow"
  end
  alias_method :ui_textarea, :ui_input

  # Segmented filter/tab pill (e.g. CAPA status filters). Consistent focus-visible
  # ring + subtle press feedback, active state uses the brand purple.
  def ui_filter_pill(active)
    base = "px-3 sm:px-4 py-2 rounded-xl text-xs sm:text-sm font-medium whitespace-nowrap min-h-[40px] " \
           "flex items-center transition-[transform,background-color] duration-150 active:scale-[0.98] " \
           "focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-1 focus-visible:ring-[#5C3984]"
    state = active ? "bg-[#5C3984] text-white" : "bg-[#F7F7FD] text-[#797C81] hover:bg-[#E9E9F9]"
    "#{base} #{state}"
  end

  # Interaction/a11y utilities to append to bespoke buttons that keep their own
  # layout classes: subtle press feedback (emil-design-eng) + focus-visible ring
  # (ui-ux-pro-max). Pass a ring color for non-brand (e.g. danger) buttons.
  def ui_press(ring = "#5C3984")
    "transition-transform duration-150 active:scale-[0.98] focus:outline-none " \
    "focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-[#{ring}]"
  end

  def current_user_credit_balance
    if current_user&.company_user
      current_user.company_user.assigned_credits || 0
    elsif current_user&.platform_admin?
      current_company&.credits.to_i
    else
      0
    end
  end

  # Toast icon helper method
  def toast_icon(type)
    case type.to_sym
    when :success
      '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'.html_safe
    when :error
      '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>'.html_safe
    when :warning
      '<svg class="w-5 h-5 text-yellow-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>'.html_safe
    when :info
      '<svg class="w-5 h-5 text-blue-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>'.html_safe
    else
      '<svg class="w-5 h-5 text-gray-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>'.html_safe
    end
  end

  # Toast background color helper method
  def toast_bg_color(type)
    case type.to_sym
    when :success then "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]"
    when :error then "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500"
    when :warning then "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-yellow-500"
    when :info then "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-blue-500"
    else "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-gray-400"
    end
  end

  def user_profile_image_url(user)
    return nil unless user&.profile_image&.attached?

    user.profile_image.blob.service.url(
      user.profile_image.blob.key,
      expires_in: 1.hour,
      filename: user.profile_image.blob.filename,
      content_type: nil,        # don't pass content_type
      disposition: "inline"
    )
  end

  def signed_file_url(attachment, disposition: "attachment")
    return nil unless attachment&.attached?

    attachment.blob.service.url(
      attachment.blob.key,
      expires_in: 1.hour,
      filename: attachment.blob.filename,
      content_type: nil,
      disposition: disposition
    )
  end

  # Check if current user is a viewer (read-only role)
  def viewer?
    current_user&.company_user&.company_viewer?
  end

  # Check if current user can modify resources
  def can_modify?
    !viewer?
  end

  # Returns the notification title in the current locale (for in-app display).
  def notification_display_title(notification)
    notification.title_in_locale(I18n.locale)
  rescue I18n::MissingTranslationData, KeyError, ArgumentError
    notification.title
  end
end
