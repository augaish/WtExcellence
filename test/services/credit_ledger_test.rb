require "test_helper"

# F13 — assistant queries reduced a balance while every usage total stayed at
# zero, because each usage screen carried its own hardcoded list of AI actions
# and none of them mentioned the assistant.
class CreditLedgerTest < ActiveSupport::TestCase
  test "every charged action is reported by the usage screens" do
    charged = CreditService::CREDIT_COSTS.reject { |_action, cost| cost.zero? }.keys

    charged.each do |action|
      assert_includes CreditService::LEDGER_ACTIONS, action,
        "#{action} costs credits but is missing from LEDGER_ACTIONS, so it would be charged silently"
    end
  end

  test "the assistant query is a charged, reported action" do
    assert_operator CreditService.get_cost("PLATFORM_ASSISTANT_QUERY"), :>, 0
    assert_includes CreditService::LEDGER_ACTIONS, "PLATFORM_ASSISTANT_QUERY"
  end
end
