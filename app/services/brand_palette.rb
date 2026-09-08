# A company's brand colours, with the WTE palette as the fallback.
#
# A company that has set nothing gets exactly the platform's own colours, so
# branding is additive: nothing changes until an admin chooses to change it.
#
# Contrast is checked rather than trusted. A company can pick any colour it
# likes for its own marketing, but a primary used behind white button text has
# to stay readable, so a colour that fails is reported and the WTE default is
# used instead of quietly making the product unusable.
class BrandPalette
  # The platform's own identity.
  DEFAULT_PRIMARY = "#5C3984".freeze
  DEFAULT_ACCENT  = "#F6EEFF".freeze

  HEX_PATTERN = /\A#\h{6}\z/

  # WCAG AA for normal text. White-on-primary is the button pattern used
  # throughout the product, so this is the threshold that matters.
  MINIMUM_CONTRAST = 4.5

  def initialize(company)
    @company = company
  end

  def primary
    usable?(@company&.brand_primary_color) ? @company.brand_primary_color : DEFAULT_PRIMARY
  end

  def accent
    valid_hex?(@company&.brand_accent_color) ? @company.brand_accent_color : DEFAULT_ACCENT
  end

  # True when the company chose a primary that had to be rejected, so the UI can
  # say why rather than silently ignoring the setting.
  def primary_rejected?
    valid_hex?(@company&.brand_primary_color) && !usable?(@company.brand_primary_color)
  end

  def self.valid_hex?(value)
    value.to_s.match?(HEX_PATTERN)
  end

  # Contrast ratio against white, per WCAG 2.2.
  def self.contrast_with_white(hex)
    return 0 unless valid_hex?(hex)

    (1.05) / (relative_luminance(hex) + 0.05)
  end

  def self.relative_luminance(hex)
    r, g, b = hex.delete_prefix("#").scan(/\h\h/).map { |part| channel(part.to_i(16) / 255.0) }
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def self.channel(value)
    value <= 0.03928 ? value / 12.92 : (((value + 0.055) / 1.055)**2.4)
  end

  def self.readable_with_white?(hex)
    contrast_with_white(hex) >= MINIMUM_CONTRAST
  end

  private

  def valid_hex?(value)
    self.class.valid_hex?(value)
  end

  # A primary is only used if white text stays legible on it.
  def usable?(value)
    valid_hex?(value) && self.class.readable_with_white?(value)
  end
end
