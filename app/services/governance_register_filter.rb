# Search, ownership and work queues for the three governance registers.
#
# The review found none of them filterable: a manager could not reach "my
# overdue treatments", "critical vendors awaiting review" or "commitments due
# this week" without reading the whole list. Built once here rather than three
# times, so a queue behaves the same wherever it appears.
#
# Queues are expressed in SQL rather than by loading and rejecting in Ruby, so
# the counts stay honest as the registers grow.
class GovernanceRegisterFilter
  Queue = Struct.new(:key, :scope, keyword_init: true)

  # Per register: which columns a search looks at, and the queues offered.
  # "mine" is always present, because "what is on my desk" is the question a
  # register is opened to answer.
  CONFIGS = {
    "Risk" => {
      search_columns: %w[title description],
      queues: %w[all mine open above_appetite needs_acceptance review_overdue closed]
    },
    "Vendor" => {
      search_columns: %w[name category notes],
      queues: %w[all mine unassessed critical review_overdue not_approved]
    },
    "CustomerCommitment" => {
      search_columns: %w[title description customer_name],
      queues: %w[all mine overdue due_soon awaiting_acceptance fulfilled]
    }
  }.freeze

  DEFAULT_QUEUE = "all".freeze

  def initialize(scope, params:, company_user: nil, company: nil)
    @scope = scope
    @model = scope.model
    @config = CONFIGS.fetch(@model.name)
    @params = params
    @company_user = company_user
    @company = company
  end

  attr_reader :scope, :model, :config, :params, :company_user, :company

  def search_term
    params[:q].to_s.strip
  end

  def queue
    requested = params[:queue].to_s
    config[:queues].include?(requested) ? requested : DEFAULT_QUEUE
  end

  def results
    @results ||= apply_queue(apply_search(scope), queue)
  end

  def filtering?
    search_term.present? || queue != DEFAULT_QUEUE
  end

  def queues
    config[:queues]
  end

  # Counts for the queue chips, each computed against the search so the numbers
  # describe what clicking would actually show.
  def queue_counts
    @queue_counts ||= config[:queues].index_with do |key|
      apply_queue(apply_search(scope), key).count
    end
  end

  private

  def apply_search(relation)
    return relation if search_term.blank?

    clause = config[:search_columns].map { |column| "#{model.table_name}.#{column} ILIKE :term" }.join(" OR ")
    relation.where(clause, term: "%#{sanitize_like(search_term)}%")
  end

  def sanitize_like(term)
    term.gsub(/[\\%_]/) { |character| "\\#{character}" }
  end

  def apply_queue(relation, key)
    case key
    when "mine" then mine(relation)
    when "open" then relation.where.not(status: "closed")
    when "closed" then relation.where(status: "closed")
    when "above_appetite" then above_appetite(relation)
    when "needs_acceptance" then above_appetite(relation).where.not(status: "closed").where("accepted_at IS NULL OR acceptance_expires_on < ?", Date.current)
    when "review_overdue" then review_overdue(relation)
    when "not_approved" then relation.where(approval_status: %w[not_approved suspended])
    when "awaiting_acceptance" then relation.where(status: "fulfilled", acceptance_status: "pending")
    when "unassessed" then relation.where(risk_level: "unassessed")
    when "critical" then relation.where(risk_level: "critical")
    when "overdue" then relation.where(due_date: ...Date.current).where.not(status: "fulfilled")
    when "due_soon" then due_soon(relation)
    when "fulfilled" then relation.where(status: "fulfilled")
    else relation
    end
  end

  # With nobody signed in as a company member there is no "mine" to show, and an
  # empty result is a truer answer than the whole list.
  def mine(relation)
    return relation.none if company_user.nil?

    relation.where(owner_id: company_user.id)
  end

  # Current exposure is the residual score where one has been assessed, and the
  # inherent score until then — the same rule the record itself applies.
  def above_appetite(relation)
    appetite = company&.risk_appetite_score
    return relation.none if appetite.blank?

    relation.where("COALESCE(risks.residual_score, risks.inherent_score) > ?", appetite)
  end

  # Risks and vendors both carry a next review date; only risks have a status
  # that ends the need for one.
  def review_overdue(relation)
    scoped = relation.where("next_review_on < ?", Date.current)
    relation.klass.column_names.include?("status") ? scoped.where.not(status: "closed") : scoped
  end

  def due_soon(relation)
    relation.where(due_date: Date.current..CustomerCommitment::DUE_SOON_DAYS.days.from_now.to_date)
            .where.not(status: "fulfilled")
  end
end
