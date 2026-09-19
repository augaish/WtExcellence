# One password rule for the whole product: set once, checked everywhere a
# password is chosen (invitation, reset, admin change, sign-up).
module PasswordRule
  MIN_LENGTH = 10

  # Letters and digits both present; length checked separately.
  def self.strong?(password)
    value = password.to_s
    value.length >= MIN_LENGTH && value.match?(/\p{L}/) && value.match?(/\d/)
  end

  def self.message(locale = I18n.locale)
    I18n.t("password_rule.message", min: MIN_LENGTH, locale: locale)
  end
end
