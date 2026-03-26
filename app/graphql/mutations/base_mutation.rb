module Mutations
  class BaseMutation < GraphQL::Schema::Mutation
    include GraphqlSupport::AuthHelpers
    include GraphqlSupport::ErrorHelpers
    include GraphqlSupport::PayloadHelpers

    null false

    private

    def scoped_payload(payload, *candidate_keys)
      return payload if payload.blank?

      hash =
        if payload.respond_to?(:to_unsafe_h)
          payload.to_unsafe_h
        elsif payload.respond_to?(:to_h)
          payload.to_h
        else
          payload
        end

      return payload unless hash.is_a?(Hash)

      candidate_keys.each do |key|
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)
        return hash[key.to_sym] if hash.key?(key.to_sym)
      end

      payload
    end

    def persist_proof_points!(proof_points, fallback_relation)
      ProofLedgerPersistenceService.persist_from_payload!(
        proof_points: proof_points,
        current_user_id: current_user_id,
        fallback_relation: fallback_relation
      )
    end
  end
end
