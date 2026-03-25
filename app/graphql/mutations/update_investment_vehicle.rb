module Mutations
  class UpdateInvestmentVehicle < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :investment_vehicle, GraphQL::Types::JSON, required: false
    argument :proof_points, [GraphQL::Types::JSON], required: false

    field :success, Boolean, null: false

    def resolve(id:, investment_vehicle: nil, proof_points: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      vehicle = InvestmentVehicle.find_by(id: id)
      raise_not_found("InvestmentVehicles.NotFound", id, "investment vehicle") if vehicle.nil?

      attrs = extract_model_attributes(scoped_payload(investment_vehicle, :investment_vehicle, :investmentVehicle))
      assign_filtered_attributes(vehicle, attrs)
      vehicle.updated_by_id = current_user_id if vehicle.respond_to?(:updated_by_id=)
      vehicle.updated_at_utc = Time.now.utc if vehicle.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        vehicle.save!
        persist_proof_points!(proof_points, "investment_vehicle_id" => vehicle.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "InvestmentVehicles.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end
  end
end
