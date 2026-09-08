# Turns the organizational structure into an SVG chart: boxes joined by
# reporting lines, coloured by the group each unit belongs to.
#
# Written as a service for the same reasons as ProcessDiagramRenderer — no new
# dependency, no npm, and a layout that can be unit-tested and renders
# identically server-side and in tests. Nobody positions anything by hand: the
# chart is a picture of the structure, so moving a box would only ever make it
# lie.
#
# Each box carries the unit's id, so the page can open its mandate when clicked.
class OrgChartRenderer
  BOX_WIDTH = 190
  BOX_HEIGHT = 56
  H_GAP = 18
  V_GAP = 64
  PADDING = 24

  # House palette, used where a unit's group has no colour of its own.
  PRIMARY = "#5C3984".freeze
  BORDER = "#E3E3E3".freeze
  TEXT = "#0D1120".freeze
  MUTED = "#797C81".freeze
  LINE = "#C9CBD1".freeze

  def self.render(units, locale: I18n.locale)
    new(units, locale: locale).render
  end

  def initialize(units, locale: I18n.locale)
    @units = units.to_a
    @locale = locale
    @children = @units.group_by(&:parent_id)
    @positions = {}
  end

  attr_reader :units, :locale

  def render
    return empty_svg if units.empty?

    layout!
    <<~SVG.html_safe
      <svg viewBox="0 0 #{canvas_width} #{canvas_height}" width="#{canvas_width}" height="#{canvas_height}"
           xmlns="http://www.w3.org/2000/svg" role="group"
           aria-label="#{escape(I18n.t('org_structure.chart.title', locale: locale))}">
        <title>#{escape(I18n.t('org_structure.chart.title', locale: locale))}</title>
        #{connectors_svg}
        #{boxes_svg}
      </svg>
    SVG
  end

  private

  # Roots are the units whose parent is absent from the set being drawn, so a
  # filtered subtree still renders rather than coming out blank.
  def roots
    ids = units.map(&:id).to_set
    units.reject { |unit| unit.parent_id && ids.include?(unit.parent_id) }
  end

  # A tidy tree: a leaf takes one column, a parent is centred over its children.
  def layout!
    cursor = PADDING
    roots.each do |root|
      cursor = place(root, depth: 0, cursor: cursor)
      cursor += H_GAP
    end
  end

  def place(unit, depth:, cursor:)
    kids = (@children[unit.id] || [])
    y = PADDING + depth * (BOX_HEIGHT + V_GAP)

    if kids.empty?
      @positions[unit.id] = { x: cursor, y: y, unit: unit }
      return cursor + BOX_WIDTH
    end

    child_start = cursor
    child_cursor = cursor
    kids.each_with_index do |child, index|
      child_cursor += H_GAP if index.positive?
      child_cursor = place(child, depth: depth + 1, cursor: child_cursor)
    end

    # Centre the parent over the span its children occupy.
    centre = child_start + ((child_cursor - child_start) / 2.0) - (BOX_WIDTH / 2.0)
    @positions[unit.id] = { x: [ centre, child_start ].max, y: y, unit: unit }

    [ child_cursor, @positions[unit.id][:x] + BOX_WIDTH ].max
  end

  def canvas_width
    (@positions.values.map { |p| p[:x] + BOX_WIDTH }.max.to_i + PADDING)
  end

  def canvas_height
    (@positions.values.map { |p| p[:y] + BOX_HEIGHT }.max.to_i + PADDING)
  end

  def connectors_svg
    @positions.values.filter_map do |position|
      parent_id = position[:unit].parent_id
      parent = @positions[parent_id]
      next if parent.nil?

      child_x = position[:x] + BOX_WIDTH / 2
      parent_x = parent[:x] + BOX_WIDTH / 2
      parent_bottom = parent[:y] + BOX_HEIGHT
      elbow = parent_bottom + (V_GAP / 2)

      # Elbowed rather than diagonal, which is how an org chart is read.
      %(<path d="M #{parent_x} #{parent_bottom} V #{elbow} H #{child_x} V #{position[:y]}"
              fill="none" stroke="#{LINE}" stroke-width="1.5" />)
    end.join("\n")
  end

  def boxes_svg
    @positions.values.map { |position| box_svg(position) }.join("\n")
  end

  def box_svg(position)
    unit = position[:unit]
    colour = group_colour(unit)
    name = unit.display_name(locale)

    # The whole box is the control, so the click target is the box a reader
    # already sees rather than a small link inside it.
    <<~BOX
      <g class="org-chart-node" role="button" tabindex="0"
         data-action="click->org-chart#select keydown.enter->org-chart#select"
         data-org-chart-unit-id-param="#{unit.id}"
         aria-label="#{escape(name)}">
        <rect x="#{position[:x]}" y="#{position[:y]}" width="#{BOX_WIDTH}" height="#{BOX_HEIGHT}"
              rx="8" fill="#FFFFFF" stroke="#{BORDER}" stroke-width="1" />
        <rect x="#{position[:x]}" y="#{position[:y]}" width="5" height="#{BOX_HEIGHT}"
              rx="2" fill="#{colour}" />
        <text x="#{position[:x] + 16}" y="#{position[:y] + 23}" font-size="12" font-weight="600"
              fill="#{TEXT}">#{escape(truncate_label(name))}</text>
        <text x="#{position[:x] + 16}" y="#{position[:y] + 40}" font-size="10" fill="#{MUTED}">#{escape(subtitle(unit))}</text>
      </g>
    BOX
  end

  def subtitle(unit)
    [ unit.code, I18n.t("org_structure.level_n", level: unit.level, locale: locale, default: "L#{unit.level}") ]
      .compact_blank.join(" · ")
  end

  def group_colour(unit)
    unit.org_group&.color.presence || PRIMARY
  end

  # SVG has no text wrapping, so a long name is cut rather than allowed to run
  # over the next box. The full name stays available in the box's label.
  def truncate_label(name)
    name.to_s.length > 26 ? "#{name[0, 25]}…" : name.to_s
  end

  def empty_svg
    %(<svg viewBox="0 0 100 40" width="100" height="40" xmlns="http://www.w3.org/2000/svg"></svg>).html_safe
  end

  def escape(text)
    ERB::Util.html_escape(text.to_s)
  end
end
