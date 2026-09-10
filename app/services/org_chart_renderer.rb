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
  BOX_HEIGHT = 68
  TEXT_INSET = 16
  # A name longer than this is wrapped onto a second line; longer still is cut.
  LINE_CHARS = 24
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
           xmlns="http://www.w3.org/2000/svg" role="group" direction="#{direction}"
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
              fill="none" stroke="#{LINE}" stroke-width="1.5" data-child-id="#{position[:unit].id}" />)
    end.join("\n")
  end

  def boxes_svg
    @positions.values.map { |position| box_svg(position) }.join("\n")
  end

  def box_svg(position)
    unit = position[:unit]
    colour = group_colour(unit)
    name = unit.display_name(locale)
    lines = wrap_label(name)

    # The whole box is the control, so the click target is the box a reader
    # already sees rather than a small link inside it.
    <<~BOX
      <g class="org-chart-node" role="button" tabindex="0"
         data-action="click->org-chart#select keydown.enter->org-chart#select"
         data-org-chart-unit-id-param="#{unit.id}"
         data-unit-id="#{unit.id}" data-parent-id="#{unit.parent_id}"
         data-search-text="#{escape([ name, unit.code ].compact_blank.join(' ').downcase)}"
         aria-label="#{escape(name)}">
        <rect x="#{position[:x]}" y="#{position[:y]}" width="#{BOX_WIDTH}" height="#{BOX_HEIGHT}"
              rx="8" fill="#FFFFFF" stroke="#{BORDER}" stroke-width="1" />
        <rect x="#{accent_x(position)}" y="#{position[:y]}" width="5" height="#{BOX_HEIGHT}"
              rx="2" fill="#{colour}" />
        <text x="#{text_x(position)}" y="#{position[:y] + 22}" font-size="12" font-weight="600"
              text-anchor="#{text_anchor}" fill="#{TEXT}">#{escape(lines[0])}</text>
        <text x="#{text_x(position)}" y="#{position[:y] + 37}" font-size="12" font-weight="600"
              text-anchor="#{text_anchor}" fill="#{TEXT}">#{escape(lines[1])}</text>
        <text x="#{text_x(position)}" y="#{position[:y] + 54}" font-size="10"
              text-anchor="#{text_anchor}" fill="#{MUTED}">#{escape(subtitle(unit))}</text>
      </g>
    BOX
  end

  # Text is anchored to the side it is read from. Inside an Arabic page an SVG
  # inherits right-to-left direction, so a start-anchored label at the left
  # edge would run out of the box to the left — which is exactly what happened.
  def rtl?
    locale.to_s.start_with?("ar")
  end

  def direction
    rtl? ? "rtl" : "ltr"
  end

  def text_anchor
    rtl? ? "end" : "start"
  end

  def text_x(position)
    rtl? ? position[:x] + BOX_WIDTH - TEXT_INSET : position[:x] + TEXT_INSET
  end

  def accent_x(position)
    rtl? ? position[:x] + BOX_WIDTH - 5 : position[:x]
  end

  def subtitle(unit)
    [ unit.code, I18n.t("org_structure.level_n", level: unit.level, locale: locale, default: "L#{unit.level}") ]
      .compact_blank.join(" · ")
  end

  def group_colour(unit)
    unit.org_group&.color.presence || PRIMARY
  end

  # SVG has no text wrapping, so the name is broken into two lines by hand at
  # word boundaries. Anything beyond the second line is cut; the full name
  # stays available in the box's label and the text tree beside the chart.
  def wrap_label(name)
    words = name.to_s.split(/\s+/)
    lines = [ "" ]
    words.each do |word|
      candidate = [ lines.last, word ].reject(&:empty?).join(" ")
      if candidate.length <= LINE_CHARS || lines.last.empty?
        lines[-1] = candidate
      else
        lines << word
      end
    end
    lines = lines.first(2)
    lines[1] = "#{lines[1][0, LINE_CHARS - 1]}…" if lines[1] && (lines[1].length > LINE_CHARS || words.join(" ").length > lines.join(" ").length)
    lines[0] = "#{lines[0][0, LINE_CHARS - 1]}…" if lines[0].length > LINE_CHARS && lines[1].nil?
    [ lines[0], lines[1].to_s ]
  end

  def empty_svg
    %(<svg viewBox="0 0 100 40" width="100" height="40" xmlns="http://www.w3.org/2000/svg"></svg>).html_safe
  end

  def escape(text)
    ERB::Util.html_escape(text.to_s)
  end
end
