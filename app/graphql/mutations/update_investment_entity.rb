module Mutations
  class UpdateInvestmentEntity < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :investment_entity, GraphQL::Types::JSON, required: false
    argument :proof_points, [GraphQL::Types::JSON], required: false

    field :success, Boolean, null: false

    def resolve(id:, investment_entity: nil, proof_points: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      entity = InvestmentEntity.find_by(id: id)
      raise_not_found("InvestmentEntities.NotFound", id, "investment entity") if entity.nil?

      attrs = extract_model_attributes(scoped_payload(investment_entity, :investment_entity, :investmentEntity))
      assign_filtered_attributes(entity, attrs)
      entity.updated_by_id = current_user_id if entity.respond_to?(:updated_by_id=)
      entity.updated_at_utc = Time.now.utc if entity.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        entity.save!
        persist_proof_points!(proof_points, "investment_entity_id" => entity.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "InvestmentEntities.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end
  end
end
