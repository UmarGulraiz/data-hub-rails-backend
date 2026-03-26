module Mutations
  class DeleteProofLedger < Mutations::BaseMutation
    argument :id, ID, required: true

    field :success, Boolean, null: false

    def resolve(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      record = ProofLedger.find_by(id: id)
      raise_not_found("ProofLedgers.NotFound", id, "proof_ledger") if record.nil?

      record.destroy!
      { success: true }
    end
  end
end
