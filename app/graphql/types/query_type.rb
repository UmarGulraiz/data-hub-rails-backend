module Types
  class QueryType < Types::BaseObject
    include GraphqlSupport::AuthHelpers
    include GraphqlSupport::ErrorHelpers
    include GraphqlSupport::PayloadHelpers

    field :analytics_database_insights_overview, GraphQL::Types::JSON, null: false
    field :analytics_database_insights_distributions, GraphQL::Types::JSON, null: false
    field :analytics_team, GraphQL::Types::JSON, null: false
    field :user, GraphQL::Types::JSON, null: false do
      argument :id, ID, required: true
    end
    field :investor_search, GraphQL::Types::JSON, null: false do
      argument :page, Integer, required: false
      argument :limit, Integer, required: false
      argument :column_filter, Types::ColumnFilterInputType, required: false
      argument :sort, [Types::SortInputType], required: false
    end
    field :export_investors_by_filters, String, null: false do
      argument :columns, [String], required: false
      argument :column_filter, Types::ColumnFilterInputType, required: false
      argument :sort, [Types::SortInputType], required: false
    end
    field :export_investors_by_ids, String, null: false do
      argument :selected_ids, [ID], required: false
      argument :columns, [String], required: false
    end
    field :investor, GraphQL::Types::JSON, null: false do
      argument :id, ID, required: true
    end
    field :investment_vehicle, GraphQL::Types::JSON, null: false do
      argument :id, ID, required: true
    end
    field :investment_strategy, GraphQL::Types::JSON, null: false do
      argument :id, ID, required: true
    end
    field :investor_contacts, GraphQL::Types::JSON, null: false do
      argument :investor_id, ID, required: true
    end
    field :investment_entities, GraphQL::Types::JSON, null: false do
      argument :investor_id, ID, required: true
    end
    field :regions, GraphQL::Types::JSON, null: false
    field :currencies, GraphQL::Types::JSON, null: false
    field :countries, GraphQL::Types::JSON, null: false do
      argument :region_ids, [ID], required: false
    end
    field :cities_by_country, GraphQL::Types::JSON, null: false do
      argument :id, ID, required: true
    end
    field :organizations, GraphQL::Types::JSON, null: false
    field :ideal_investor_profiles, GraphQL::Types::JSON, null: false do
      argument :organization_ids, [ID], required: false
    end
    field :proof_ledger, GraphQL::Types::JSON, null: false do
      argument :filter, Types::RelationFilterInputType, required: true
    end
    field :proof_ledger_comments, GraphQL::Types::JSON, null: false do
      argument :filter, Types::RelationFilterInputType, required: true
      argument :field_id, String, required: false
    end

    def analytics_database_insights_overview
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      GraphqlApi::AnalyticsOverviewService.new.call
    end

    def analytics_database_insights_distributions
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      GraphqlApi::AnalyticsDistributionsService.new.call
    end

    def analytics_team
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      GraphqlApi::AnalyticsTeamService.new.call
    end

    def user(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      user = User.find_by(id: id)
      raise_not_found("Users.NotFound", id, "user") if user.nil?

      details = UserDetail.find_by(id: user.id)
      deep_camelize(
        id: user.id,
        email: user.email,
        email_confirmed: user.email_confirmed,
        created_at_utc: user.created_at_utc,
        user_details: {
          first_name: details&.first_name,
          last_name: details&.last_name
        },
        organization: {}
      )
    end

    def investor_search(page: 1, limit: 10, column_filter: nil, sort: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      investors_service.search(page: page, limit: limit, column_filter: column_filter || {}, sort: sort || [])
    end

    def export_investors_by_filters(columns: nil, column_filter: nil, sort: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      investors_service.export_by_filters(columns: columns, column_filter: column_filter || {}, sort: sort || [])
    end

    def export_investors_by_ids(selected_ids: nil, columns: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)
      investors_service.export_by_ids(selected_ids: selected_ids, columns: columns)
    end

    def investor(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      payload = investors_service.show(id)
      raise_not_found("Investors.NotFound", id, "investor") if payload.nil?

      payload
    end

    def investment_vehicle(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      vehicle = InvestmentVehicle.find_by(id: id)
      raise_not_found("InvestmentVehicles.NotFound", id, "investment vehicle") if vehicle.nil?

      serialize_record(vehicle)
    end

    def investment_strategy(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      strategy = InvestmentStrategy.includes(:investment_strategy_region_focuses, :investment_strategy_country_focuses).find_by(id: id)
      raise_not_found("InvestmentStrategies.NotFound", id, "investment strategy") if strategy.nil?

      payload = serialize_record(strategy)
      payload["regionInvestmentFocus"] = strategy.investment_strategy_region_focuses.includes(:region).map do |focus|
        next nil if focus.region.nil?

        { "id" => focus.region.id, "name" => focus.region.name }
      end.compact
      payload["countryInvestmentFocus"] = strategy.investment_strategy_country_focuses.includes(:country).map do |focus|
        next nil if focus.country.nil?

        { "id" => focus.country.id, "name" => focus.country.name }
      end.compact
      payload
    end

    def investor_contacts(investor_id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      contacts = InvestorContact.where(investor_id: investor_id).order(created_at_utc: :desc, id: :asc)
      { "data" => contacts.map { |contact| serialize_record(contact) } }
    end

    def investment_entities(investor_id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      vehicle_ids = InvestmentVehicle.where(investor_id: investor_id).pluck(:id).map(&:to_s)
      entities = if vehicle_ids.empty?
                   InvestmentEntity.none
                 else
                   InvestmentEntity.where(investment_vehicle_id: vehicle_ids).order(created_at_utc: :desc, id: :asc)
                 end
      { "data" => entities.map { |entity| serialize_record(entity) } }
    end

    def regions
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      {
        "data" => Region.order(:name).map do |region|
          {
            id: region.id,
            name: region.name,
            code: region.code,
            description: region.description,
            created_at_utc: region.created_at_utc,
            updated_at_utc: region.updated_at_utc
          }
        end.map { |payload| deep_camelize(payload) }
      }
    end

    def currencies
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      {
        "data" => Currency.order(:code, :name).map do |currency|
          deep_camelize(
            id: currency.id,
            name: currency.name,
            symbol: currency.symbol,
            code: currency.code,
            decimal_places: currency.decimal_places,
            is_active: currency.is_active,
            created_at_utc: currency.created_at_utc,
            updated_at_utc: currency.updated_at_utc
          )
        end
      }
    end

    def countries(region_ids: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      scope = Country.order(:name)
      ids = Array(region_ids).compact_blank
      scope = scope.where(region_id: ids) if ids.any?

      {
        "data" => scope.map do |country|
          deep_camelize(
            id: country.id,
            region_id: country.region_id,
            name: country.name,
            iso_code: country.iso_code,
            iso3_code: country.iso3code,
            calling_code: country.calling_code,
            currency_id: country.currency_id,
            created_at_utc: country.created_at_utc,
            updated_at_utc: country.updated_at_utc
          )
        end
      }
    end

    def cities_by_country(id:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      cities = City.where(country_id: id).order(:name)
      { "data" => cities.map { |city| serialize_record(city) } }
    end

    def organizations
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      {
        "items" => OrganizationProfile.order(:company_name).map do |organization|
          {
            value: organization.id,
            text: organization.company_name
          }
        end
      }
    end

    def ideal_investor_profiles(organization_ids: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      scope = IdealInvestorProfile.order(:name)
      ids = Array(organization_ids).compact_blank
      scope = scope.where(organization_profile_id: ids) if ids.any?

      {
        "data" => scope.map do |profile|
          deep_camelize(
            id: profile.id,
            organization_profile_id: profile.organization_profile_id,
            name: profile.name,
            description: profile.description,
            fund_profile_id: profile.fund_profile_id,
            briefing: profile.briefing,
            min_check_size: profile.min_check_size,
            max_check_size: profile.max_check_size,
            thematic_keywords: profile.thematic_keywords || [],
            asset_class: profile.asset_class || [],
            sector_focus: profile.sector_focus || [],
            investor_type: profile.investor_type || [],
            maturity_focus: profile.maturity_focus || [],
            stage_focus: profile.stage_focus || [],
            strategy_focus: profile.strategy_focus || [],
            region_headquarter_id: profile.region_headquarter_id,
            country_headquarter_id: profile.country_headquarter_id,
            city_headquarter: profile.city_headquarter,
            created_by_id: profile.created_by_id,
            updated_by_id: profile.updated_by_id,
            created_at_utc: profile.created_at_utc,
            updated_at_utc: profile.updated_at_utc
          )
        end
      }
    end

    def proof_ledger(filter:)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      relation = proof_ledger_relation(filter)
      rows = ProofLedger.includes(:created_by, :updated_by).where(relation).order(created_at_utc: :desc)
      { "data" => rows.map { |row| serialize_proof_point(row) } }
    end

    def proof_ledger_comments(filter:, field_id: nil)
      authorize_roles!(*GraphqlSupport::AuthHelpers::ALL_ROLES)

      relation = proof_ledger_relation(filter)
      scope = ProofLedgerComment.includes(:created_by, :updated_by).where(relation)
      scope = scope.where(field_id: field_id.to_s) if field_id.present?

      { "data" => scope.order(created_at_utc: :asc).map { |row| serialize_comment(row) } }
    end

    private

    def investors_service
      @investors_service ||= GraphqlApi::InvestorsService.new
    end

    def proof_ledger_relation(filter)
      relation = GraphqlApi::ProofLedgerFilterService.new.relation_from(filter)
      return relation if relation.present?

      raise_execution_error(
        code: "ProofLedger.NoFilterSpecified",
        detail: "No filter was specified for the ProofLedger query.",
        status: 400,
        type: "https://tools.ietf.org/html/rfc7231#section-6.5.1"
      )
    end

    def serialize_proof_point(row)
      payload = serialize_record(row)
      payload["createdBy"] = row.created_by&.user_name
      payload["updatedBy"] = row.updated_by&.user_name
      payload
    end

    def serialize_comment(row)
      payload = serialize_record(row)
      payload["createdBy"] = row.created_by&.user_name
      payload["updatedBy"] = row.updated_by&.user_name
      payload
    end
  end
end
