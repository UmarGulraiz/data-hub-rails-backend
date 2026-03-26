module GraphqlApi
  class InvestorsService
    include GraphqlSupport::PayloadHelpers

    def search(page:, limit:, column_filter:, sort:)
      page_number = [page.to_i, 1].max
      per_page = limit.to_i.positive? ? limit.to_i : 10
      per_page = [per_page, 100].min

      investors = base_scope
      name_filter = input_value(column_filter, :name).to_s.strip

      if name_filter.present?
        term = "%#{name_filter.downcase}%"
        investors = investors
                    .left_outer_joins(:investment_vehicles)
                    .left_outer_joins(investment_vehicles: :investment_vehicle_investment_strategies)
                    .left_outer_joins(
                      investment_vehicles: {
                        investment_vehicle_investment_strategies: :investment_strategy
                      }
                    )
                    .where(
                      "LOWER(public.investors.name) LIKE :term OR LOWER(public.investment_vehicles.name) LIKE :term OR LOWER(public.investment_strategies.name) LIKE :term",
                      term: term
                    )
                    .distinct
      end

      investors = investors.order(Arel.sql(order_sql(sort.to_a.first || {})))
      total = investors.count
      total_pages = (total.to_f / per_page).ceil

      {
        total: total,
        page: page_number,
        total_pages: total_pages,
        limit: per_page,
        has_next: page_number < total_pages,
        has_prev: page_number > 1,
        data: investors.offset((page_number - 1) * per_page).limit(per_page).to_a.map { |investor| serialize_investor(investor) }
      }.then { |payload| deep_camelize(payload) }
    end

    def export_by_filters(columns:, column_filter:, sort:)
      investors = base_export_scope
      name_filter = input_value(column_filter, :name).to_s.strip

      if name_filter.present?
        term = "%#{name_filter.downcase}%"
        investors = investors
                    .left_outer_joins(:investment_vehicles)
                    .left_outer_joins(investment_vehicles: :investment_vehicle_investment_strategies)
                    .left_outer_joins(
                      investment_vehicles: {
                        investment_vehicle_investment_strategies: :investment_strategy
                      }
                    )
                    .where(
                      "LOWER(public.investors.name) LIKE :term OR LOWER(public.investment_vehicles.name) LIKE :term OR LOWER(public.investment_strategies.name) LIKE :term",
                      term: term
                    )
                    .distinct
      end

      build_csv(investors.order(Arel.sql(order_sql(sort.to_a.first || {}))), columns)
    end

    def export_by_ids(selected_ids:, columns:)
      investors = base_export_scope.where(id: Array(selected_ids).map(&:to_s).reject(&:blank?))
      build_csv(investors, columns)
    end

    def show(id)
      investor = Investor.preload(:location, :investment_vehicles, :investment_strategies, location: { country: :region }).find_by(id: id)
      return nil if investor.nil?

      deep_camelize(serialize_investor_detail(investor))
    end

    private

    def base_scope
      Investor.preload(
        :investor_contacts,
        investment_strategies: [
          { investment_strategy_region_focuses: :region },
          { investment_strategy_country_focuses: :country }
        ],
        location: { country: :region },
        investment_vehicles: {
          investment_vehicle_investment_strategies: {
            investment_strategy: [
              { investment_strategy_region_focuses: :region },
              { investment_strategy_country_focuses: :country }
            ]
          }
        }
      )
    end

    def base_export_scope
      Investor.preload(
        :investor_contacts,
        investment_strategies: [
          { investment_strategy_region_focuses: :region },
          { investment_strategy_country_focuses: :country }
        ],
        location: { country: :region },
        investment_vehicles: {
          investment_vehicle_investment_strategies: {
            investment_strategy: [
              { investment_strategy_region_focuses: :region },
              { investment_strategy_country_focuses: :country }
            ]
          }
        }
      )
    end

    def order_sql(sort_item)
      sort_field = input_value(sort_item, :field).to_s
      sort_direction = input_value(sort_item, :direction).to_s.downcase == "desc" ? "DESC" : "ASC"

      case sort_field
      when "updatedAtUtc"
        "public.investors.updated_at_utc #{sort_direction} NULLS LAST"
      else
        "public.investors.name #{sort_direction}, public.investors.id ASC"
      end
    end

    def serialize_investor(investor)
      strategies = strategy_records_for(investor)

      {
        id: investor.id,
        name: investor.name,
        website_url: investor.website_url,
        type: investor.type,
        updated_at_utc: investor.updated_at_utc,
        qualified: investor.qualified,
        contacts_count: investor.investor_contacts.size,
        location: serialize_location(investor.location),
        investment_vehicles: investor.investment_vehicles.map do |vehicle|
          {
            id: vehicle.id,
            name: vehicle.name
          }
        end,
        investment_strategies: strategies.map { |strategy| serialize_strategy(strategy) }
      }
    end

    def serialize_location(location)
      return nil if location.nil?

      {
        id: location.id,
        address_line1: location.address_line1,
        city: location.city,
        country: {
          id: location.country&.id,
          name: location.country&.name,
          region: {
            id: location.country&.region&.id,
            name: location.country&.region&.name
          }
        }
      }
    end

    def serialize_strategy(strategy)
      {
        id: strategy.id,
        name: strategy.name,
        asset_class_focus: strategy.asset_class_focus || [],
        sector_investment_focus: strategy.sector_investment_focus || [],
        maturity_focus: strategy.maturity_focus || [],
        stage_focus: strategy.stage_focus || [],
        investor_type_focus: strategy.investor_type_focus || [],
        region_investment_focus: strategy.investment_strategy_region_focuses.map { |focus| focus.region&.name }.compact,
        country_investment_focus: strategy.investment_strategy_country_focuses.map { |focus| focus.country&.name }.compact
      }
    end

    def serialize_investor_detail(investor)
      payload = serialize_record(investor)
      location = investor.location || Location.find_by(id: investor.location_id)
      payload["currencyId"] = investor.investor_currencies.first&.currency_id
      payload["location"] = deep_camelize(serialize_location(location))
      payload["country"] = location&.country_id
      payload["city"] = location&.city
      payload["addressLine1"] = location&.address_line1
      payload["investmentVehicles"] = investor.investment_vehicles.map { |vehicle| serialize_record(vehicle) }
      payload["investmentStrategies"] = investor.investment_strategies.map { |strategy| serialize_record(strategy) }
      payload["contactsCount"] = investor.investor_contacts.count
      vehicle_ids = investor.investment_vehicles.map { |vehicle| vehicle.id.to_s }
      payload["investmentEntitiesCount"] = if vehicle_ids.empty?
                                             0
                                           else
                                             InvestmentEntity.where(investment_vehicle_id: vehicle_ids).count
                                           end
      payload
    end

    def build_csv(investors, requested_columns)
      require "csv"

      columns = Array(requested_columns).map(&:to_s).reject { |column| column.blank? || column == "select" || column == "actions" }
      columns = ["name", "websiteUrl", "investorType", "headquarter", "updatedAtUtc"] if columns.empty?

      CSV.generate(headers: true) do |csv|
        csv << columns
        investors.to_a.each do |investor|
          csv << columns.map { |column| csv_value_for(investor, column) }
        end
      end
    end

    def csv_value_for(investor, column)
      strategies = strategy_records_for(investor)

      case column
      when "name" then investor.name
      when "websiteUrl" then investor.website_url
      when "investorType" then investor.type
      when "headquarter" then [investor.location&.city, investor.location&.country&.name, investor.location&.country&.region&.name].compact.join(", ")
      when "headquarterRegion" then investor.location&.country&.region&.name
      when "headquarterCountry" then investor.location&.country&.name
      when "headquarterCity" then investor.location&.city
      when "updatedAtUtc" then investor.updated_at_utc
      when "assetClassFocus" then strategies.flat_map { |strategy| Array(strategy.asset_class_focus) }.uniq.join(", ")
      when "sectorInvestmentFocus" then strategies.flat_map { |strategy| Array(strategy.sector_investment_focus) }.uniq.join(", ")
      when "regionInvestmentFocus" then strategies.flat_map { |strategy| strategy.investment_strategy_region_focuses.map { |focus| focus.region&.name } }.compact.uniq.join(", ")
      when "countryInvestmentFocus" then strategies.flat_map { |strategy| strategy.investment_strategy_country_focuses.map { |focus| focus.country&.name } }.compact.uniq.join(", ")
      when "maturityFocus" then strategies.flat_map { |strategy| Array(strategy.maturity_focus) }.uniq.join(", ")
      when "investorTypeFocus" then strategies.flat_map { |strategy| Array(strategy.investor_type_focus) }.uniq.join(", ")
      when "stageFocus" then strategies.flat_map { |strategy| Array(strategy.stage_focus) }.uniq.join(", ")
      when "numberOfContacts" then investor.investor_contacts.size
      when "saturation" then nil
      when "investmentVehiclesCount" then investor.investment_vehicles.size
      when "investmentVehicleNames" then investor.investment_vehicles.map(&:name).compact.join(", ")
      when "qualified" then investor.qualified
      when "organization" then investor.respond_to?(:organization_profile_id) ? investor.organization_profile_id : nil
      when "iip" then nil
      else
        attribute = column.to_s.underscore
        investor.respond_to?(attribute) ? investor.public_send(attribute) : nil
      end
    end

    def input_value(input, key)
      hash = input.respond_to?(:to_h) ? input.to_h : input
      hash[key] || hash[key.to_s]
    end

    def strategy_records_for(investor)
      from_vehicles = investor.investment_vehicles
                              .flat_map(&:investment_vehicle_investment_strategies)
                              .map(&:investment_strategy)
      from_investor = Array(investor.investment_strategies)

      (from_vehicles + from_investor).compact.uniq(&:id)
    end
  end
end
