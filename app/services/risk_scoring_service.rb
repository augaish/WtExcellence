class RiskScoringService
  # Standard 5x5 likelihood x impact risk matrix.
  def self.calculate(likelihood:, impact:)
    likelihood.to_i * impact.to_i
  end
end
