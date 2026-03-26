module Mutations
  class DeleteInvestorContact < Mutations::BaseMutation
    argument :id, ID, required: true

    field :success, Boolean, null: false

    def resolve(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      contact = InvestorContact.find_by(id: id)
      raise_not_found("InvestorContacts.NotFound", id, "investor contact") if contact.nil?

      ActiveRecord::Base.transaction do
        # Clear optional references so a contact can be removed safely.
        Investor.where(primary_contact_id: contact.id).update_all(primary_contact_id: nil)
        InvestmentStrategy.where(investor_contact_id: contact.id).update_all(investor_contact_id: nil)
        InvestmentVehicle.where(key_person_id: contact.id).update_all(key_person_id: nil)
        # Avoid loading OrganizationContact model here because it currently raises
        # an enum-definition error unrelated to contact deletion.
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(
            :sanitize_sql_array,
            [
              "UPDATE public.organization_contacts SET investor_contact_reference_id = NULL WHERE investor_contact_reference_id = ?",
              contact.id
            ]
          )
        )
        # `field_history` table is singular in this database, so avoid relying on
        # ActiveRecord's default pluralized table mapping here.
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(
            :sanitize_sql_array,
            [
              "UPDATE public.field_history SET investor_contact_id = NULL WHERE investor_contact_id = ?",
              contact.id
            ]
          )
        )
        ProofLedger.where(investor_contact_id: contact.id).update_all(investor_contact_id: nil)
        ProofLedgerComment.where(investor_contact_id: contact.id).update_all(investor_contact_id: nil)

        # Clear join rows that require a contact id.
        InvestmentVehicleKeyContact.where(investor_contact_id: contact.id).delete_all
        IipProspectInvestorContact.where(investor_contact_id: contact.id).delete_all
        # `investor_contacts_related` table is singular in schema.
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(
            :sanitize_sql_array,
            [
              "DELETE FROM public.investor_contacts_related WHERE contact_id = ? OR related_contact_id = ?",
              contact.id,
              contact.id
            ]
          )
        )

        contact.destroy!
      end

      { success: true }
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      raise_execution_error(
        code: "InvestorContacts.DeleteFailed",
        detail: e.message,
        status: 400,
        type: "https://tools.ietf.org/html/rfc7231#section-6.5.1"
      )
    end
  end
end
