# Turns a structured diagram into an SVG swimlane picture.
#
# Deliberately NOT a drawing canvas: the user never positions anything. Elements
# are laid out left-to-right in the order they were authored, each in the lane
# of its performer, with the external participant in its own pool at the bottom.
#
# Written as a service (no new dependency, no npm) so the layout is unit-testable
# and renders identically server-side and in tests.
class ProcessDiagramRenderer
  LANE_HEIGHT = 120
  LANE_LABEL_WIDTH = 150
  NODE_WIDTH = 150
  NODE_HEIGHT = 60
  H_GAP = 60
  PADDING = 20
  # The external participant is its own pool: a gap and its own border keep it
  # apart from the organisation's lanes.
  POOL_GAP = 18

  # House palette.
  PRIMARY = "#5C3984".freeze
  TINT = "#F6EEFF".freeze
  BORDER = "#E3E3E3".freeze
  TEXT = "#0D1120".freeze
  MUTED = "#797C81".freeze
  DANGER = "#DC2626".freeze

  def self.render(diagram)
    new(diagram).render
  end

  def initialize(diagram)
    @diagram = diagram
    @elements = diagram.elements.to_a
    @flows = diagram.flows.to_a
  end

  def render
    return empty_svg if @elements.empty?

    layout!
    <<~SVG.html_safe
      <svg viewBox="0 0 #{canvas_width} #{canvas_height}" width="100%" height="#{canvas_height}"
           xmlns="http://www.w3.org/2000/svg" role="img" aria-label="#{escape(@diagram.display_name)}">
        #{defs}
        #{lanes_svg}
        #{flows_svg}
        #{nodes_svg}
      </svg>
    SVG
  end

  # Exposed for tests: which lane and column each element landed in.
  def layout
    layout!
    @positions
  end

  private

  def layout!
    return if @positions

    @pools = @diagram.lanes
    @positions = {}
    column_for_pool = Hash.new(0)

    # Elements advance left-to-right in author order. Each element takes the
    # next free column overall, so a reader follows the process across lanes
    # without back-tracking.
    column = 0
    @elements.each do |element|
      pool_index = @pools.index(element.lane) || 0
      @positions[element.id] = { column: column, lane: pool_index }
      column_for_pool[element.lane] += 1
      column += 1
    end
  end

  def canvas_width
    LANE_LABEL_WIDTH + (@elements.size * (NODE_WIDTH + H_GAP)) + PADDING
  end

  def canvas_height
    (@pools.size * LANE_HEIGHT) + (PADDING * 2) + (external_index ? POOL_GAP : 0)
  end

  def external_index
    @pools.index(PpDiagramElement::EXTERNAL_POOL)
  end

  def lane_y(index)
    PADDING + index * LANE_HEIGHT + (external_index && index >= external_index ? POOL_GAP : 0)
  end

  def node_x(column)
    LANE_LABEL_WIDTH + PADDING + column * (NODE_WIDTH + H_GAP)
  end

  def node_y(lane)
    lane_y(lane) + (LANE_HEIGHT - NODE_HEIGHT) / 2
  end

  def defs
    <<~SVG
      <defs>
        <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5"
                markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#{MUTED}"/>
        </marker>
        <marker id="arrow-msg" viewBox="0 0 10 10" refX="9" refY="5"
                markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#{PRIMARY}"/>
        </marker>
        <marker id="arrow-bad" viewBox="0 0 10 10" refX="9" refY="5"
                markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#{DANGER}"/>
        </marker>
      </defs>
    SVG
  end

  def lanes_svg
    @pools.each_with_index.map do |pool, index|
      y = lane_y(index)
      external = (pool == PpDiagramElement::EXTERNAL_POOL)
      label = external ? I18n.t("architect.external_pool") : pool
      <<~SVG
        <g>
          <rect x="#{PADDING}" y="#{y}" width="#{canvas_width - PADDING * 2}" height="#{LANE_HEIGHT}"
                fill="#{index.even? ? '#FFFFFF' : '#FAFAFC'}" stroke="#{external ? PRIMARY : BORDER}" stroke-width="#{external ? 1.5 : 1}"/>
          <rect x="#{PADDING}" y="#{y}" width="#{LANE_LABEL_WIDTH}" height="#{LANE_HEIGHT}"
                fill="#{external ? TINT : '#F7F7FD'}" stroke="#{BORDER}"/>
          <text x="#{PADDING + LANE_LABEL_WIDTH / 2}" y="#{y + LANE_HEIGHT / 2}"
                text-anchor="middle" dominant-baseline="middle"
                font-size="12" font-weight="600" fill="#{external ? PRIMARY : TEXT}">#{escape(truncate(label, 20))}</text>
        </g>
      SVG
    end.join
  end

  def nodes_svg
    @elements.map do |element|
      pos = @positions[element.id]
      x = node_x(pos[:column])
      y = node_y(pos[:lane])
      shape_for(element, x, y)
    end.join
  end

  def shape_for(element, x, y)
    cx = x + NODE_WIDTH / 2
    cy = y + NODE_HEIGHT / 2
    label = escape(truncate(element.title.presence || element.type_label, 22))
    sub = escape(truncate(element.performer.to_s, 20))

    body =
      if element.event?
        radius = NODE_HEIGHT / 2
        stroke_width = element.element_type == "endEvent" ? 3 : 2
        %(<circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="#FFFFFF" stroke="#{PRIMARY}" stroke-width="#{stroke_width}"/>)
      elsif element.gateway?
        half = NODE_HEIGHT / 2
        %(<polygon points="#{cx},#{cy - half} #{cx + half},#{cy} #{cx},#{cy + half} #{cx - half},#{cy}"
                   fill="#FFFFFF" stroke="#{PRIMARY}" stroke-width="2"/>)
      elsif element.artifact?
        %(<rect x="#{x}" y="#{y}" width="#{NODE_WIDTH}" height="#{NODE_HEIGHT}" rx="4"
                fill="#FAFAFC" stroke="#{BORDER}" stroke-dasharray="4 3"/>)
      else
        %(<rect x="#{x}" y="#{y}" width="#{NODE_WIDTH}" height="#{NODE_HEIGHT}" rx="8"
                fill="#{TINT}" stroke="#{PRIMARY}"/>)
      end

    <<~SVG
      <g class="diagram-node" data-element-id="#{element.id}" data-x="#{x}" data-width="#{NODE_WIDTH}" style="cursor: grab;">
        #{body}
        #{element.task? ? task_glyph(element.element_type, x + 6, y + 6) : ''}
        <text x="#{cx}" y="#{element.event? || element.gateway? ? cy + NODE_HEIGHT / 2 + 14 : cy - 4}"
              text-anchor="middle" dominant-baseline="middle"
              font-size="11" font-weight="600" fill="#{TEXT}">#{label}</text>
        #{sub.empty? ? '' : %(<text x="#{cx}" y="#{cy + 12}" text-anchor="middle" font-size="10" fill="#{MUTED}">#{sub}</text>)}
      </g>
    SVG
  end

  # The BPMN task marker in the box corner: person, hand, gear, envelope,
  # table, script. Small strokes, so they print at any size.
  def task_glyph(type, x, y)
    stroke = %(fill="none" stroke="#{PRIMARY}" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round")
    shape = case type
    when "userTask" then %(<circle cx="#{x + 6}" cy="#{y + 4}" r="2.5" #{stroke}/><path d="M #{x + 1} #{y + 12} Q #{x + 6} #{y + 6} #{x + 11} #{y + 12}" #{stroke}/>)
    when "manualTask" then %(<path d="M #{x + 2} #{y + 7} h 8 M #{x + 2} #{y + 4} h 7 M #{x + 2} #{y + 10} h 7 M #{x + 2} #{y + 4} v 6" #{stroke}/>)
    when "serviceTask" then %(<circle cx="#{x + 6}" cy="#{y + 6}" r="3" #{stroke}/><path d="M #{x + 6} #{y} v 2 M #{x + 6} #{y + 10} v 2 M #{x} #{y + 6} h 2 M #{x + 10} #{y + 6} h 2" #{stroke}/>)
    when "sendTask", "receiveTask" then %(<rect x="#{x + 1}" y="#{y + 2}" width="10" height="8" rx="1" #{stroke}/><path d="M #{x + 1} #{y + 2} l 5 4 l 5 -4" #{stroke}/>)
    when "businessRuleTask" then %(<rect x="#{x + 1}" y="#{y + 2}" width="10" height="8" #{stroke}/><path d="M #{x + 1} #{y + 5} h 10 M #{x + 4} #{y + 5} v 5" #{stroke}/>)
    when "scriptTask" then %(<path d="M #{x + 3} #{y + 2} h 7 M #{x + 2} #{y + 5} h 7 M #{x + 3} #{y + 8} h 7 M #{x + 2} #{y + 11} h 7" #{stroke}/>)
    else ""
    end
    %(<g aria-hidden="true">#{shape}</g>)
  end

  # Arrows leave the right edge of a box and enter the left edge of the next,
  # each in its own vertical channel so two arrows never share a line. A
  # backward arrow (to an earlier column) dips below the lane instead of
  # cutting through the boxes in between.
  def flows_svg
    channels = Hash.new(0)
    @flows.map do |flow|
      from = @positions[flow.from_element_id]
      to = @positions[flow.to_element_id]
      next if from.nil? || to.nil?

      x1 = node_x(from[:column]) + NODE_WIDTH
      y1 = node_y(from[:lane]) + NODE_HEIGHT / 2
      x2 = node_x(to[:column])
      y2 = node_y(to[:lane]) + NODE_HEIGHT / 2
      backward = to[:column] <= from[:column]
      gap_key = [ from[:column], to[:column] ].min
      slot = channels[gap_key]
      channels[gap_key] += 1
      offset = ((slot + 1) / 2) * 8 * (slot.odd? ? 1 : -1)

      # A sequence flow that crosses pools is a modelling error — draw it red so
      # the mistake is visible, matching what the evaluator will report.
      invalid = flow.kind == "sequence" && flow.crosses_pools?
      colour = invalid ? DANGER : (flow.kind == "message" ? PRIMARY : MUTED)
      marker = invalid ? "arrow-bad" : (flow.kind == "message" ? "arrow-msg" : "arrow")
      dash = flow.kind == "message" ? %(stroke-dasharray="6 4") : ""

      # The straight midpoint is where the bend handle rests; a bent arrow
      # passes through that point moved by the offset the user dragged.
      mid_x = (x1 + x2) / 2 + offset
      mid_y = (y1 + y2) / 2
      if flow.bent?
        bx = mid_x + flow.bend_dx
        by = mid_y + flow.bend_dy
        # The curve passes through the dragged point itself (a quadratic curve
        # reaches only halfway to its control point, so the control point is
        # placed twice as far out).
        path = "M #{x1} #{y1} Q #{2 * bx - mid_x} #{2 * by - mid_y}, #{x2} #{y2}"
        handle_x, handle_y = bx, by
      elsif backward
        # Out of the source's right edge, down under the lane, back along it,
        # and up into the target's left edge.
        below = [ node_y(from[:lane]), node_y(to[:lane]) ].max + NODE_HEIGHT + 14 + slot * 8
        path = "M #{x1} #{y1} H #{x1 + 14} V #{below} H #{x2 - 14} V #{y2} H #{x2}"
        handle_x, handle_y = (x1 + x2) / 2, below
      else
        # An elbow: straight out, a vertical run in the channel, straight in.
        path = "M #{x1} #{y1} H #{mid_x} V #{y2} H #{x2}"
        handle_x, handle_y = mid_x, mid_y
      end

      label = flow.label.presence
      <<~SVG
        <g>
          <path d="#{path}" fill="none" stroke="#{colour}" stroke-width="1.5" #{dash} marker-end="url(##{marker})"/>
          #{label ? %(<text x="#{handle_x}" y="#{handle_y - 8}" text-anchor="middle" font-size="10" fill="#{colour}">#{escape(truncate(label, 18))}</text>) : ''}
          <circle class="diagram-bend" data-flow-id="#{flow.id}" data-mid-x="#{mid_x}" data-mid-y="#{mid_y}"
                  cx="#{handle_x}" cy="#{handle_y}" r="5" fill="#FFFFFF" stroke="#{colour}" stroke-width="1.5" opacity="0.6" style="cursor: move;"/>
        </g>
      SVG
    end.compact.join
  end

  def empty_svg
    <<~SVG.html_safe
      <svg viewBox="0 0 400 120" width="100%" height="120" xmlns="http://www.w3.org/2000/svg" role="img"
           aria-label="#{escape(I18n.t('architect.empty_diagram'))}">
        <rect x="1" y="1" width="398" height="118" rx="8" fill="#FAFAFC" stroke="#{BORDER}" stroke-dasharray="6 4"/>
        <text x="200" y="60" text-anchor="middle" dominant-baseline="middle"
              font-size="12" fill="#{MUTED}">#{escape(I18n.t('architect.empty_diagram'))}</text>
      </svg>
    SVG
  end

  def truncate(text, length)
    value = text.to_s
    value.length > length ? "#{value[0, length - 1]}…" : value
  end

  def escape(text)
    ERB::Util.html_escape(text.to_s)
  end
end
