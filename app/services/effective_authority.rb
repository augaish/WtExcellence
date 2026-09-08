# Who may actually decide something today.
#
# The matrix says who holds an authority; delegations say who is exercising it
# right now. Reading only one of them gives the wrong answer, which is why a
# register on its own never settles the question.
#
# Answers for a given amount, because an authority split into bands places its
# holders differently at different values.
class EffectiveAuthority
  Holder = Struct.new(:org_unit, :source, :delegation, :limit, keyword_init: true) do
    # "matrix" — named directly by the executive matrix
    # "delegated" — exercising it under a delegation in force today
    def delegated?
      source == "delegated"
    end
  end

  def initialize(authority, on: Date.current)
    @authority = authority
    @on = on
  end

  attr_reader :authority, :on

  # Everyone who may finally authorize `amount` today: the band's own holders
  # plus anyone holding a delegation in force from one of them.
  def authorizers_for(amount = nil)
    band = band_for(amount)
    return [] if band.nil?

    matrix_holders(band) + delegated_holders(band)
  end

  # The delegations of this authority in force today.
  def delegations_in_force
    @delegations_in_force ||= authority.delegations.select { |delegation| delegation.in_force?(on) }
  end

  private

  def band_for(amount)
    return authority.bands.first if amount.nil?

    authority.bands.find { |band| band.covers?(amount) }
  end

  def matrix_holders(band)
    band.assignments
      .select { |assignment| assignment.level == AuthorityLevel::FINAL_KEY && assignment.org_unit }
      .map { |assignment| Holder.new(org_unit: assignment.org_unit, source: "matrix", limit: band.max_amount) }
  end

  # A delegation only confers authority the delegating position actually holds
  # in this band, so delegating from a unit that is not a holder here adds
  # nobody.
  def delegated_holders(band)
    holder_ids = band.assignments
      .select { |assignment| assignment.level == AuthorityLevel::FINAL_KEY }
      .filter_map(&:org_unit_id)

    delegations_in_force
      .select { |delegation| holder_ids.include?(delegation.from_org_unit_id) }
      .map do |delegation|
        Holder.new(org_unit: delegation.to_org_unit, source: "delegated",
          delegation: delegation, limit: delegation.effective_limit)
      end
  end
end
