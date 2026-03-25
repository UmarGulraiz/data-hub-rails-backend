require "securerandom"

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
      country_id = attrs.delete("country")
      city = attrs.delete("city")
      address_line1 = attrs.delete("address_line1")
      primary_contact = attrs.delete("primary_contact")
      assign_filtered_attributes(contact, attrs)
      contact.updated_by_id = current_user_id if contact.respond_to?(:updated_by_id=)
      contact.updated_at_utc = Time.now.utc if contact.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        contact.save!
        sync_contact_location!(contact, country_id: country_id, city: city, address_line1: address_line1)
        sync_primary_contact!(contact, primary_contact)
        persist_proof_points!(proof_points, "investor_contact_id" => contact.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "InvestorContacts.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end

    private

    def sync_contact_location!(contact, country_id:, city:, address_line1:)
      return if country_id.nil? && city.nil? && address_line1.nil?

      normalized_country_id = country_id.to_s.strip
      normalized_city = city.to_s
      normalized_address_line1 = address_line1.to_s

      location = contact.location
      if location.nil?
        return if normalized_country_id.blank?

        location = Location.create!(
          id: SecureRandom.uuid,
          country_id: normalized_country_id,
          city: normalized_city,
          address_line1: normalized_address_line1,
          location_type: "primary",
          created_by_id: current_user_id || contact.created_by_id,
          created_at_utc: Time.now.utc
        )
        contact.location_id = location.id
        contact.save!
        return
      end

      location.country_id = normalized_country_id if country_id.present? && normalized_country_id.present?
      location.city = normalized_city unless city.nil?
      location.address_line1 = normalized_address_line1 unless address_line1.nil?
      location.updated_by_id = current_user_id if location.respond_to?(:updated_by_id=)
      location.updated_at_utc = Time.now.utc if location.respond_to?(:updated_at_utc=)
      location.save! if location.changed?
    end

    def sync_primary_contact!(contact, primary_contact)
      return if primary_contact.nil?

      should_be_primary = ActiveModel::Type::Boolean.new.cast(primary_contact)
      investor = contact.investor
      return if investor.nil?

      if should_be_primary
        investor.primary_contact_id = contact.id
      elsif investor.primary_contact_id == contact.id
        investor.primary_contact_id = nil
      else
        return
      end

      investor.updated_by_id = current_user_id if investor.respond_to?(:updated_by_id=)
      investor.updated_at_utc = Time.now.utc if investor.respond_to?(:updated_at_utc=)
      investor.save!
    end
  end
end
