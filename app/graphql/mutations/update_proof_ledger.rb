module Mutations
  class UpdateProofLedger < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :proof_ledger, GraphQL::Types::JSON, required: true

    field :success, Boolean, null: false

    def resolve(id:, proof_ledger:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      record = ProofLedger.find_by(id: id)
      raise_not_found("ProofLedgers.NotFound", id, "proof_ledger") if record.nil?

      attrs = extract_model_attributes(scoped_payload(proof_ledger, :proof_ledger, :proofLedger))
      assign_filtered_attributes(record, attrs)
      record.updated_by_id = current_user_id if record.respond_to?(:updated_by_id=)
      record.updated_at_utc = Time.now.utc if record.respond_to?(:updated_at_utc=)
      record.save!

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(
        code: "ProofLedgers.UpdateFailed",
        detail: e.record.errors.full_messages.join(", "),
        status: 400,
        type: "https://tools.ietf.org/html/rfc7231#section-6.5.1"
      )
    end
  end
end
