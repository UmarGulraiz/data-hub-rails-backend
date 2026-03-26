module Mutations
  class DeleteInvestmentEntity < Mutations::BaseMutation
    argument :id, ID, required: true

    field :success, Boolean, null: false

    def resolve(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      entity = InvestmentEntity.find_by(id: id)
      raise_not_found("InvestmentEntities.NotFound", id, "investment entity") if entity.nil?

      ActiveRecord::Base.transaction do
        # Clear optional references first to satisfy foreign-key constraints.
        ProofLedger.where(investment_entity_id: entity.id).update_all(investment_entity_id: nil)
        ProofLedgerComment.where(investment_entity_id: entity.id).update_all(investment_entity_id: nil)

        # `field_history` table is singular in this database schema.
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(
            :sanitize_sql_array,
            [
              "UPDATE public.field_history SET investment_entity_id = NULL WHERE investment_entity_id = ?",
              entity.id
            ]
          )
        )

        # Investments are entity-owned records with required entity relation.
        Investment.where(investment_entity_id: entity.id).delete_all

        entity.destroy!
      end
      { success: true }
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      raise_execution_error(
        code: "InvestmentEntities.DeleteFailed",
        detail: e.message,
        status: 400,
        type: "https://tools.ietf.org/html/rfc7231#section-6.5.1"
      )
    end
  end
end
