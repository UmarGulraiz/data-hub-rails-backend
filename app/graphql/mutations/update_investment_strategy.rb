module Mutations
  class UpdateInvestmentStrategy < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :investment_strategy, GraphQL::Types::JSON, required: false
    argument :proof_points, [GraphQL::Types::JSON], required: false

    field :success, Boolean, null: false

    def resolve(id:, investment_strategy: nil, proof_points: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      strategy = InvestmentStrategy.find_by(id: id)
      raise_not_found("InvestmentStrategies.NotFound", id, "investment strategy") if strategy.nil?

      attrs = extract_model_attributes(
        scoped_payload(investment_strategy, :investment_strategy, :investmentStrategy)
      )
      region_ids = attrs.delete("region_investment_focus")
      country_ids = attrs.delete("country_investment_focus")

      assign_filtered_attributes(strategy, attrs)
      strategy.updated_by_id = current_user_id if strategy.respond_to?(:updated_by_id=)
      strategy.updated_at_utc = Time.now.utc if strategy.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        strategy.save!
        replace_region_focuses(strategy, region_ids) if region_ids.is_a?(Array)
        replace_country_focuses(strategy, country_ids) if country_ids.is_a?(Array)
        persist_proof_points!(proof_points, "investment_strategy_id" => strategy.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "InvestmentStrategies.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end

    private

    def replace_region_focuses(strategy, region_ids)
      InvestmentStrategyRegionFocus.where(investment_strategy_id: strategy.id).delete_all
      region_ids.map(&:presence).compact.each do |region_id|
        InvestmentStrategyRegionFocus.create!(investment_strategy_id: strategy.id, region_id: region_id)
      end
    end

    def replace_country_focuses(strategy, country_ids)
      InvestmentStrategyCountryFocus.where(investment_strategy_id: strategy.id).delete_all
      country_ids.map(&:presence).compact.each do |country_id|
        InvestmentStrategyCountryFocus.create!(investment_strategy_id: strategy.id, country_id: country_id)
      end
    end
  end
end
