# Raises a CAPA from a governance record (Risk / Vendor / CustomerCommitment),
# pre-filled from the source and linked back via Capa#origin. This is the
# GRC → QMS integration: governance findings are worked through the mature CAPA
# process rather than a parallel workflow.
class GovernanceCapaService
  class UnsupportedOriginError < StandardError; end

  def self.create_from(origin:, company:, user:)
    new(origin: origin, company: company, user: user).create
  end

  def initialize(origin:, company:, user:)
    @origin = origin
    @company = company
    @user = user
  end

  def create
    capa = Capa.new(capa_attributes)
    capa.company_id = @company.id
    capa.created_by_id = @user&.id
    capa.origin = @origin
    capa.analysis_method = "manual"
    capa.save!
    capa
  end

  private

  def capa_attributes
    case @origin
    when Risk
      {
        title: "Mitigation: #{@origin.title}",
        description: @origin.description.presence ||
          "Corrective/preventive action for risk \"#{@origin.title}\" (inherent level: #{@origin.inherent_level}).",
        source: "Risk Management",
        priority: risk_priority
      }
    when Vendor
      {
        title: "Vendor action: #{@origin.name}",
        description: "Corrective/preventive action for vendor \"#{@origin.name}\" (risk level: #{@origin.risk_level}).",
        source: "Vendor Assessment",
        priority: @origin.risk_level.in?(%w[high critical]) ? "high" : "medium"
      }
    when CustomerCommitment
      {
        title: "Commitment: #{@origin.title}",
        description: @origin.description.presence ||
          "Action to fulfil customer commitment \"#{@origin.title}\" for #{@origin.customer_name}.",
        source: "Customer Commitment",
        priority: @origin.past_due? ? "high" : "medium"
      }
    else
      raise UnsupportedOriginError, "Cannot raise a CAPA from #{@origin.class}"
    end
  end

  def risk_priority
    case @origin.inherent_level
    when "critical", "high" then "high"
    when "medium" then "medium"
    else "low"
    end
  end
end
