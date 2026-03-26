require "securerandom"

module Mutations
  class CreateInvestorContact < Mutations::BaseMutation
    argument :investor_id, ID, required: true

    field :id, ID, null: false

    def resolve(investor_id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      investor = Investor.find_by(id: investor_id)
      raise_not_found("Investors.NotFound", investor_id, "investor") if investor.nil?

      contact = InvestorContact.new(
        id: SecureRandom.uuid,
        investor_id: investor.id,
        created_by_id: current_user_id,
        created_at_utc: Time.now.utc
      )

      if contact.save
        { id: contact.id }
      else
        raise_execution_error(code: "InvestorContacts.CreateFailed", detail: contact.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
      end
    end
  end
end
