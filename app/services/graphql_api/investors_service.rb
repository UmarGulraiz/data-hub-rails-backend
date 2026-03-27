module GraphqlApi
  class InvestorsService
    include GraphqlSupport::PayloadHelpers

    def search(page:, limit:, filter:, column_filter:, sort:)
      page_number = [page.to_i, 1].max
      per_page = limit.to_i.positive? ? limit.to_i : 10
      per_page = [per_page, 100].min

      filtered = filtered_scope(base_scope, filter: filter, column_filter: column_filter)
      filtered_ids = filtered.except(:order).reselect("public.investors.id").distinct

      investors = base_scope.where(id: filtered_ids).order(Arel.sql(order_sql(sort)))
      total = filtered_ids.count
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

    def export_by_filters(columns:, filter:, column_filter:, sort:)
      filtered = filtered_scope(base_export_scope, filter: filter, column_filter: column_filter)
      filtered_ids = filtered.except(:order).reselect("public.investors.id").distinct
      investors = base_export_scope.where(id: filtered_ids).order(Arel.sql(order_sql(sort)))
      build_csv(investors, columns)
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

    def filtered_scope(scope, filter:, column_filter:)
      investors = apply_name_filter(scope, input_value(column_filter, :name).to_s.strip)
      investors = apply_column_filters(investors, column_filter)
      investors = apply_advanced_filters(investors, filter)
      investors.distinct
    end

    def apply_name_filter(scope, name_filter)
      return scope if name_filter.blank?

      term = "%#{name_filter.downcase}%"
      scope
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

    def apply_column_filters(scope, column_filter)
      filters = normalize_column_filters(column_filter)
      ids = matching_investor_ids(filters, "and")
      return scope if ids.nil?

      scope.where(id: ids)
    end

    def apply_advanced_filters(scope, filter)
      join_operator = input_value(filter, :joinOperator).to_s.downcase == "or" ? "or" : "and"
      filters = normalize_grouped_filters(input_value(filter, :filterList))
      ids = matching_investor_ids(filters, join_operator)
      return scope if ids.nil?

      scope.where(id: ids)
    end

    def normalize_column_filters(column_filter)
      hash = input_hash(column_filter)

      hash.each_with_object([]) do |(key, raw_value), filters|
        next if key.to_s == "name"

        values = normalize_values(raw_value)
        next if values.empty?

        filters << {
          id: key.to_s,
          operator: values.length > 1 ? "inArray" : "eq",
          value: values.length > 1 ? values : values.first
        }
      end
    end

    def normalize_grouped_filters(filter_list)
      input_hash(filter_list).flat_map do |id, rules|
        Array(rules).map do |rule|
          rule_hash = input_hash(rule)
          {
            id: id.to_s,
            operator: rule_hash["operator"].presence || "eq",
            value: rule_hash["value"]
          }
        end
      end
    end

    def matching_investor_ids(filters, join_operator)
      normalized = filters.filter_map { |filter| normalize_filter_condition(filter) }
      return nil if normalized.empty?

      require "set"

      id_sets = normalized.map { |filter| filter_scope(filter).distinct.pluck(:id).map(&:to_s).to_set }
      return [] if id_sets.empty?

      combined = id_sets.shift || Set.new
      id_sets.each do |ids|
        combined = join_operator == "or" ? (combined | ids) : (combined & ids)
      end
      combined.to_a
    end

    def normalize_filter_condition(filter)
      filter_hash = input_hash(filter)
      id = filter_hash["id"].to_s
      operator = filter_hash["operator"].presence || "eq"
      values = normalize_values(filter_hash["value"])

      return nil if id.blank?
      return nil if values.empty? && !%w[isEmpty isNotEmpty].include?(operator)

      {
        id: id,
        operator: operator,
        values: values
      }
    end

    def filter_scope(filter)
      case filter[:id]
      when "investorType"
        apply_scalar_filter(Investor.all, "public.investors.type", filter)
      when "qualified"
        apply_boolean_filter(Investor.all, "public.investors.qualified", filter)
      when "organization"
        apply_scalar_filter(Investor.all, "public.investors.organization_profile_id", filter)
      when "iip"
        scope = Investor.joins(
          "INNER JOIN public.ideal_investor_profiles ON public.ideal_investor_profiles.organization_profile_id = public.investors.organization_profile_id"
        )
        apply_scalar_filter(scope, "public.ideal_investor_profiles.id", filter)
      when "headquarterCity"
        apply_text_filter(Investor.left_outer_joins(:location), "public.locations.city", filter)
      when "headquarterCountry"
        scope = Investor.left_outer_joins(location: :country)
        apply_scalar_filter(scope, "public.countries.id", filter)
      when "headquarterRegion"
        scope = Investor.left_outer_joins(location: { country: :region })
        apply_scalar_filter(scope, "public.regions.id", filter)
      when "assetClassFocus"
        scope = strategy_filter_scope
        apply_array_filter(scope, "public.investment_strategies.asset_class_focus", filter)
      when "sectorInvestmentFocus"
        scope = strategy_filter_scope
        apply_array_filter(scope, "public.investment_strategies.sector_investment_focus", filter)
      when "maturityFocus"
        scope = strategy_filter_scope
        apply_array_filter(scope, "public.investment_strategies.maturity_focus", filter)
      when "investorTypeFocus"
        scope = strategy_filter_scope
        apply_array_filter(scope, "public.investment_strategies.investor_type_focus", filter)
      when "stageFocus"
        scope = strategy_filter_scope
        apply_array_filter(scope, "public.investment_strategies.stage_focus", filter)
      when "regionInvestmentFocus"
        scope = strategy_filter_scope.joins(
          "LEFT JOIN public.investment_strategy_region_focus ON public.investment_strategy_region_focus.investment_strategy_id::text = public.investment_strategies.id::text"
        )
        apply_scalar_filter(scope, "public.investment_strategy_region_focus.region_id", filter)
      when "countryInvestmentFocus"
        scope = strategy_filter_scope.joins(
          "LEFT JOIN public.investment_strategy_country_focus ON public.investment_strategy_country_focus.investment_strategy_id::text = public.investment_strategies.id::text"
        )
        apply_scalar_filter(scope, "public.investment_strategy_country_focus.country_id", filter)
      else
        Investor.none
      end
    end

    def strategy_filter_scope
      Investor.joins(
        "LEFT JOIN public.investment_strategies ON public.investment_strategies.investor_id::text = public.investors.id::text"
      )
    end

    def apply_text_filter(scope, column, filter)
      values = filter[:values]

      case filter[:operator]
      when "eq"
        scope.where("#{column} = ?", values.first)
      when "ne"
        scope.where("#{column} IS NULL OR #{column} <> ?", values.first)
      when "iLike"
        scope.where("LOWER(COALESCE(#{column}, '')) LIKE ?", "%#{values.first.downcase}%")
      when "notILike"
        scope.where("LOWER(COALESCE(#{column}, '')) NOT LIKE ?", "%#{values.first.downcase}%")
      when "inArray"
        scope.where("#{column} IN (?)", values)
      when "notInArray"
        scope.where("#{column} IS NULL OR #{column} NOT IN (?)", values)
      when "isEmpty"
        scope.where("#{column} IS NULL OR #{column} = ''")
      when "isNotEmpty"
        scope.where("#{column} IS NOT NULL AND #{column} <> ''")
      else
        scope
      end
    end

    def apply_scalar_filter(scope, column, filter)
      values = filter[:values]

      case filter[:operator]
      when "eq"
        scope.where("#{column} = ?", values.first)
      when "ne"
        scope.where("#{column} IS NULL OR #{column} <> ?", values.first)
      when "inArray"
        scope.where("#{column} IN (?)", values)
      when "notInArray"
        scope.where("#{column} IS NULL OR #{column} NOT IN (?)", values)
      when "isEmpty"
        scope.where("#{column} IS NULL")
      when "isNotEmpty"
        scope.where("#{column} IS NOT NULL")
      when "iLike", "notILike"
        apply_text_filter(scope, column, filter)
      else
        scope
      end
    end

    def apply_array_filter(scope, column, filter)
      values = filter[:values]
      normalized_values = normalize_filter_tokens(values)

      case filter[:operator]
      when "eq", "inArray"
        return scope.none if normalized_values.empty?

        scope.where(
          <<~SQL,
            EXISTS (
              SELECT 1
              FROM unnest(COALESCE(#{column}::text[], ARRAY[]::text[])) AS elem
              WHERE regexp_replace(lower(elem), '[^a-z0-9]', '', 'g') IN (?)
            )
          SQL
          normalized_values
        )
      when "ne", "notInArray"
        return scope if normalized_values.empty?

        scope.where(
          <<~SQL,
            NOT EXISTS (
              SELECT 1
              FROM unnest(COALESCE(#{column}::text[], ARRAY[]::text[])) AS elem
              WHERE regexp_replace(lower(elem), '[^a-z0-9]', '', 'g') IN (?)
            )
          SQL
          normalized_values
        )
      when "isEmpty"
        scope.where("#{column} IS NULL OR cardinality(#{column}) = 0")
      when "isNotEmpty"
        scope.where("#{column} IS NOT NULL AND cardinality(#{column}) > 0")
      else
        scope
      end
    end

    def apply_boolean_filter(scope, column, filter)
      values = filter[:values].map { |value| normalize_boolean(value) }.compact.uniq

      return scope.none if values.empty? && !%w[isEmpty isNotEmpty].include?(filter[:operator])

      case filter[:operator]
      when "eq", "inArray"
        scope.where("#{column} IN (?)", values)
      when "ne", "notInArray"
        scope.where("#{column} IS NULL OR #{column} NOT IN (?)", values)
      when "isEmpty"
        scope.where("#{column} IS NULL")
      when "isNotEmpty"
        scope.where("#{column} IS NOT NULL")
      else
        scope
      end
    end

    def normalize_values(raw_value)
      Array(raw_value)
        .flat_map { |value| value.is_a?(Array) ? value : [value] }
        .map { |value| value.is_a?(String) ? value.strip : value }
        .reject { |value| value.nil? || value == "" }
    end

    def normalize_filter_tokens(values)
      Array(values)
        .map { |value| value.to_s.strip.downcase.gsub(/[^a-z0-9]/, "") }
        .reject(&:blank?)
        .uniq
    end

    def normalize_boolean(value)
      case value.to_s.strip.downcase
      when "true", "qualified"
        true
      when "false", "notqualified", "not qualified"
        false
      else
        nil
      end
    end

    def input_hash(input)
      hash =
        if input.respond_to?(:to_unsafe_h)
          input.to_unsafe_h
        elsif input.respond_to?(:to_h)
          input.to_h
        else
          input || {}
        end

      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

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

    def order_sql(sort_items)
      items = Array(sort_items).map { |item| item.respond_to?(:to_h) ? item.to_h : item }.compact
      items = [{ "field" => "name", "direction" => "asc" }] if items.empty?

      clauses = items.map { |item| order_clause_for(item) }.compact
      clauses = ["public.investors.name ASC NULLS LAST"] if clauses.empty?
      clauses << "public.investors.id ASC"
      clauses.uniq.join(", ")
    end

    def order_clause_for(sort_item)
      sort_field = input_value(sort_item, :field).to_s
      sort_direction = input_value(sort_item, :direction).to_s.downcase == "desc" ? "DESC" : "ASC"

      expression =
        case sort_field
        when "name" then "public.investors.name"
        when "websiteUrl" then "public.investors.website_url"
        when "investorType" then "public.investors.type"
        when "updatedAtUtc" then "public.investors.updated_at_utc"
        when "qualified" then "public.investors.qualified"
        when "headquarterCity"
          "(SELECT l.city FROM public.locations l WHERE l.id::text = public.investors.location_id::text LIMIT 1)"
        when "headquarterCountry"
          <<~SQL.squish
            (SELECT c.name
             FROM public.locations l
             LEFT JOIN public.countries c ON c.id::text = l.country_id::text
             WHERE l.id::text = public.investors.location_id::text
             LIMIT 1)
          SQL
        when "headquarterRegion"
          <<~SQL.squish
            (SELECT r.name
             FROM public.locations l
             LEFT JOIN public.countries c ON c.id::text = l.country_id::text
             LEFT JOIN public.regions r ON r.id::text = c.region_id::text
             WHERE l.id::text = public.investors.location_id::text
             LIMIT 1)
          SQL
        when "numberOfContacts"
          "(SELECT COUNT(*) FROM public.investor_contacts ic WHERE ic.investor_id::text = public.investors.id::text)"
        when "investmentVehiclesCount"
          "(SELECT COUNT(*) FROM public.investment_vehicles iv WHERE iv.investor_id::text = public.investors.id::text)"
        when "investmentVehicleNames"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT iv.name, ', ' ORDER BY iv.name)
             FROM public.investment_vehicles iv
             WHERE iv.investor_id::text = public.investors.id::text)
          SQL
        when "assetClassFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT focus.value, ', ' ORDER BY focus.value)
             FROM public.investment_strategies s
             LEFT JOIN LATERAL unnest(COALESCE(s.asset_class_focus::text[], ARRAY[]::text[])) AS focus(value) ON TRUE
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "sectorInvestmentFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT focus.value, ', ' ORDER BY focus.value)
             FROM public.investment_strategies s
             LEFT JOIN LATERAL unnest(COALESCE(s.sector_investment_focus::text[], ARRAY[]::text[])) AS focus(value) ON TRUE
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "maturityFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT focus.value, ', ' ORDER BY focus.value)
             FROM public.investment_strategies s
             LEFT JOIN LATERAL unnest(COALESCE(s.maturity_focus::text[], ARRAY[]::text[])) AS focus(value) ON TRUE
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "investorTypeFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT focus.value, ', ' ORDER BY focus.value)
             FROM public.investment_strategies s
             LEFT JOIN LATERAL unnest(COALESCE(s.investor_type_focus::text[], ARRAY[]::text[])) AS focus(value) ON TRUE
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "stageFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT focus.value, ', ' ORDER BY focus.value)
             FROM public.investment_strategies s
             LEFT JOIN LATERAL unnest(COALESCE(s.stage_focus::text[], ARRAY[]::text[])) AS focus(value) ON TRUE
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "regionInvestmentFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT r.name, ', ' ORDER BY r.name)
             FROM public.investment_strategies s
             LEFT JOIN public.investment_strategy_region_focus rf ON rf.investment_strategy_id::text = s.id::text
             LEFT JOIN public.regions r ON r.id::text = rf.region_id::text
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        when "countryInvestmentFocus"
          <<~SQL.squish
            (SELECT string_agg(DISTINCT c.name, ', ' ORDER BY c.name)
             FROM public.investment_strategies s
             LEFT JOIN public.investment_strategy_country_focus cf ON cf.investment_strategy_id::text = s.id::text
             LEFT JOIN public.countries c ON c.id::text = cf.country_id::text
             WHERE s.investor_id::text = public.investors.id::text)
          SQL
        end

      return nil if expression.blank?

      "#{expression} #{sort_direction} NULLS LAST"
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
      hash = input_hash(input)
      hash[key.to_s]
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
