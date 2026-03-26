module Mutations
  class UpdateInvestorContact < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :investor_contact, GraphQL::Types::JSON, required: false
    argument :proof_points, [GraphQL::Types::JSON], required: false

    field :success, Boolean, null: false

    def resolve(id:, investor_contact: nil, proof_points: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      contact = InvestorContact.find_by(id: id)
      raise_not_found("InvestorContacts.NotFound", id, "investor contact") if contact.nil?

      attrs = extract_model_attributes(scoped_payload(investor_contact, :investor_contact, :investorContact))
      assign_filtered_attributes(contact, attrs)
      contact.updated_by_id = current_user_id if contact.respond_to?(:updated_by_id=)
      contact.updated_at_utc = Time.now.utc if contact.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        contact.save!
        persist_proof_points!(proof_points, "investor_contact_id" => contact.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "InvestorContacts.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end
  end
end
