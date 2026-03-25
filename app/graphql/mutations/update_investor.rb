require "securerandom"

module Mutations
  class UpdateInvestor < Mutations::BaseMutation
    argument :id, ID, required: true
    argument :investor, GraphQL::Types::JSON, required: false
    argument :proof_points, [GraphQL::Types::JSON], required: false

    field :success, Boolean, null: false

    def resolve(id:, investor: nil, proof_points: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      record = Investor.find_by(id: id)
      raise_not_found("Investors.NotFound", id, "investor") if record.nil?

      attrs = extract_model_attributes(scoped_payload(investor, :investor))
      primary_contact_id = attrs.delete("primary_contact")
      country_id = attrs.delete("country")
      city = attrs.delete("city")
      address_line1 = attrs.delete("address_line1")
      currency_id = attrs.delete("currency_id")
      assign_filtered_attributes(record, attrs)
      if !primary_contact_id.nil?
        normalized_primary_contact_id = primary_contact_id.to_s.strip
        record.primary_contact_id = normalized_primary_contact_id.presence
      end
      record.updated_by_id = current_user_id if record.respond_to?(:updated_by_id=)
      record.updated_at_utc = Time.now.utc if record.respond_to?(:updated_at_utc=)

      ActiveRecord::Base.transaction do
        record.save!
        sync_investor_location!(record, country_id: country_id, city: city, address_line1: address_line1)
        sync_investor_currency!(record, currency_id)
        persist_proof_points!(proof_points, "investor_id" => record.id)
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      raise_execution_error(code: "Investors.UpdateFailed", detail: e.record.errors.full_messages.join(", "), status: 400, type: "https://tools.ietf.org/html/rfc7231#section-6.5.1")
    end

    private

    def sync_investor_currency!(investor, currency_id)
      return if currency_id.nil?

      normalized_currency_id = currency_id.to_s.strip
      InvestorCurrency.where(investor_id: investor.id).delete_all
      return if normalized_currency_id.blank?

      InvestorCurrency.create!(
        investor_id: investor.id,
        currency_id: normalized_currency_id
      )
    end

    def sync_investor_location!(investor, country_id:, city:, address_line1:)
      return if country_id.nil? && city.nil? && address_line1.nil?

      normalized_country_id = country_id.to_s.strip
      normalized_city = city.to_s
      normalized_address_line1 = address_line1.to_s

      location = investor.location
      if location.nil?
        return if normalized_country_id.blank?

        location = Location.create!(
          id: SecureRandom.uuid,
          country_id: normalized_country_id,
          city: normalized_city,
          address_line1: normalized_address_line1,
          location_type: "primary",
          created_by_id: current_user_id || investor.created_by_id,
          created_at_utc: Time.now.utc
        )
        investor.location_id = location.id
        investor.save!
        return
      end

      location.country_id = normalized_country_id if country_id.present? && normalized_country_id.present?
      location.city = normalized_city unless city.nil?
      location.address_line1 = normalized_address_line1 unless address_line1.nil?
      location.updated_by_id = current_user_id if location.respond_to?(:updated_by_id=)
      location.updated_at_utc = Time.now.utc if location.respond_to?(:updated_at_utc=)
      location.save! if location.changed?
    end
  end
end
