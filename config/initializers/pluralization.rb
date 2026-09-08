# Lets locale files declare their own plural rules. Arabic needs it: it has six
# plural categories where the default backend handles three, so a count of two
# would otherwise render with the wrong form.
I18n::Backend::Simple.include(I18n::Backend::Pluralization)
