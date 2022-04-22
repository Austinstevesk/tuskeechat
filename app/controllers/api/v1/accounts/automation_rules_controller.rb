class Api::V1::Accounts::AutomationRulesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_automation_rule, only: [:show, :update, :destroy, :clone]

  def index
    @automation_rules = Current.account.automation_rules.active
  end

  def create
    @automation_rule = Current.account.automation_rules.create(automation_rules_permit)
  end

  def show; end

  def update
    @automation_rule.update(automation_rules_permit)
  end

  def destroy
    @automation_rule.destroy!
    head :ok
  end

  def clone
    automation_rule = Current.account.automation_rules.find_by(id: params[:automation_rule_id])
    new_rule = automation_rule.dup
    new_rule.save
    @automation_rule = new_rule
  end

  private

  def automation_rules_permit
    params.permit(
      :name, :description, :event_name, :account_id,
      conditions: [:attribute_key, :filter_operator, :query_operator, { values: [] }],
      actions: [:action_name, { action_params: [] }]
    )
  end

  def fetch_automation_rule
    @automation_rule = Current.account.automation_rules.find_by(id: params[:id])
  end
end
