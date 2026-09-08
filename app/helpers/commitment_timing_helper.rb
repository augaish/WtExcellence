module CommitmentTimingHelper
  # "In progress / 4 days overdue" — the workflow state and the timing, shown
  # together, because neither half says what the other does. Returns just the
  # timing label when there is no day count worth quoting.
  def commitment_timing_label(commitment, on = Date.current)
    base = commitment.timing_label(on)
    days = commitment.days_overdue(on)
    return base if days.zero?

    key = commitment.fulfilled? ? "commitment_timing.days_late" : "commitment_timing.days_overdue"
    "#{base} · #{t(key, count: days)}"
  end

  # Late and overdue read as attention-needing; everything else stays quiet.
  def commitment_timing_classes(commitment, on = Date.current)
    case commitment.timing_state(on)
    when "overdue", "fulfilled_late" then "bg-[#FDEBEB] text-[#8A1C1C]"
    when "due_soon" then "bg-[#F6EEFF] text-[#0D1120]"
    else "bg-[#F7F7FD] text-[#797C81]"
    end
  end
end
