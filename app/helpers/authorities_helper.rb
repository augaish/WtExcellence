# View helpers for the Authorities page.
module AuthoritiesHelper
  # The name column edited in place: the one for the language the page shows.
  def name_field
    rtl? ? :name_ar : :name_en
  end

  # The version picker names versions only; the newest is marked as current.
  def version_option_label(matrix)
    label = "V#{matrix.version_number}"
    label += " · #{t('doa.versions.current')}" if matrix.latest_version?
    label += " · #{t('doa.review.published_on', date: l(matrix.published_at.to_date, format: :document))}" if matrix.published?
    label
  end
end
