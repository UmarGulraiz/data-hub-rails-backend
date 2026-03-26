require "securerandom"

module Mutations
  class CreateProofLedgerComment < Mutations::BaseMutation
    argument :filter, Types::RelationFilterInputType, required: true
    argument :field_id, String, required: true
    argument :comment, String, required: true
    argument :proof_ledger_comment_reply_to_id, ID, required: false

    field :id, ID, null: false

    def resolve(filter:, field_id:, comment:, proof_ledger_comment_reply_to_id: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      relation = GraphqlApi::ProofLedgerFilterService.new.relation_from(filter)
      if relation.nil?
        raise_execution_error(code: "ProofLedger.NoFilterSpecified", detail: "Either InvestorId, InvestmentVehicleId, InvestmentStrategyId, InvestorContactId or InvestmentEntityId must be provided.", status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
      end

      if field_id.to_s.blank? || comment.to_s.strip.blank?
        raise_execution_error(code: "ProofLedger.CommentInvalid", detail: "FieldId and Comment are required.", status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
      end

      reply_to_id = proof_ledger_comment_reply_to_id.presence
      if reply_to_id.present? && !ProofLedgerComment.exists?(id: reply_to_id)
        raise_not_found("ProofLedgerComments.NotFound", reply_to_id, "proof ledger comment")
      end

      record = ProofLedgerComment.new(
        relation.merge(
          id: SecureRandom.uuid,
          proof_ledger_comment_reply_to_id: reply_to_id,
          field_id: field_id.to_s,
          comment: comment.to_s.strip,
          created_by_id: current_user_id,
          created_at_utc: Time.now.utc
        )
      )

      if record.save
        { id: record.id }
      else
        raise_execution_error(code: "ProofLedger.CommentCreateFailed", detail: record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
      end
    end
  end
end
