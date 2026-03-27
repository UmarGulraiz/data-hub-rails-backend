require "test_helper"

class GraphqlApiTest < ActionDispatch::IntegrationTest
  setup do
    @now = Time.current.utc.change(usec: 0)

    @admin_role = Role.create!(
      name: "Admin",
      normalized_name: "ADMIN",
      concurrency_stamp: SecureRandom.uuid
    )
    @account_manager_role = Role.create!(
      name: "AccountManager",
      normalized_name: "ACCOUNTMANAGER",
      concurrency_stamp: SecureRandom.uuid
    )

    @admin = User.new(
      created_by_id: "seed-user",
      created_at_utc: @now,
      user_name: "admin@example.com",
      email: "admin@example.com",
      email_confirmed: true,
      security_stamp: SecureRandom.uuid,
      concurrency_stamp: SecureRandom.uuid,
      phone_number_confirmed: false,
      two_factor_enabled: false,
      lockout_enabled: true,
      access_failed_count: 0,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @admin.save!
    @admin.update_column(:created_by_id, @admin.id)

    UserRole.create!(user_id: @admin.id, role_id: @admin_role.id)
    UserDetail.create!(
      id: @admin.id,
      first_name: "Ada",
      last_name: "Admin",
      created_by_id: @admin.id,
      created_at_utc: @now
    )

    @region = Region.create!(
      name: "Asia",
      code: "AS",
      description: "Asia region",
      created_at_utc: @now
    )
    @country = Country.create!(
      region_id: @region.id,
      name: "Pakistan",
      iso_code: "PK",
      iso3code: "PAK",
      calling_code: "+92",
      created_at_utc: @now
    )
    @city = City.create!(
      name: "Karachi",
      country_id: @country.id,
      created_at_utc: @now
    )

    @organization = OrganizationProfile.create!(
      subdomain: "aqvc",
      company_name: "AQVC",
      company_legal_name: "AQVC Legal",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @ideal_investor_profile = IdealInvestorProfile.create!(
      organization_profile_id: @organization.id,
      name: "Growth Profile",
      due_date: @now + 7.days,
      target_nr_of_prospects_to_generate: 10,
      asset_class: ["funds_general"],
      sector_focus: ["fin_tech"],
      investor_type: ["family_office"],
      maturity_focus: ["emerging"],
      stage_focus: ["seed"],
      strategy_focus: ["primary"],
      created_by_id: @admin.id,
      created_at_utc: @now
    )

    @investor = Investor.create!(
      name: "Alpha Capital",
      type: "family_office",
      qualified: false,
      organization_profile_id: @organization.id,
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @vehicle = InvestmentVehicle.create!(
      investor_id: @investor.id,
      name: "Alpha Fund I",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @strategy = InvestmentStrategy.create!(
      investor_id: @investor.id,
      name: "Seed Strategy",
      sector_investment_focus: ["fin_tech"],
      stage_focus: ["seed"],
      maturity_focus: ["emerging"],
      asset_class_focus: ["funds_general"],
      strategy_focus: ["primary"],
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    InvestmentVehicleInvestmentStrategy.create!(
      investment_vehicle_id: @vehicle.id,
      investment_strategy_id: @strategy.id
    )
    InvestmentStrategyRegionFocus.create!(
      investment_strategy_id: @strategy.id,
      region_id: @region.id
    )
    InvestmentStrategyCountryFocus.create!(
      investment_strategy_id: @strategy.id,
      country_id: @country.id
    )

    @contact = InvestorContact.create!(
      investor_id: @investor.id,
      first_name: "Ina",
      last_name: "Contact",
      email: "contact@example.com",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @entity = InvestmentEntity.create!(
      investment_vehicle_id: @vehicle.id,
      name: "Alpha SPV",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @proof_ledger = ProofLedger.create!(
      investor_id: @investor.id,
      field_id: "status",
      proof_type: "manual",
      status: "active",
      version: 1,
      criteria_name: "status",
      criteria_value_new: "active",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
    @proof_comment = ProofLedgerComment.create!(
      investor_id: @investor.id,
      field_id: "status",
      comment: "Looks valid",
      created_by_id: @admin.id,
      created_at_utc: @now
    )
  end

  test "login mutation authenticates and logout clears the session" do
    login!

    investor_query = <<~GRAPHQL
      query($id: ID!) {
        investor(id: $id)
      }
    GRAPHQL
    investor_response = graphql(investor_query, variables: { id: @investor.id })
    assert_equal @investor.id, investor_response.dig("data", "investor", "id")

    logout_mutation = <<~GRAPHQL
      mutation {
        logout {
          success
        }
      }
    GRAPHQL
    logout_response = graphql(logout_mutation)
    assert_equal true, logout_response.dig("data", "logout", "success")

    unauthorized_mutation = <<~GRAPHQL
      mutation {
        createInvestor {
          id
        }
      }
    GRAPHQL
    unauthorized_response = graphql(unauthorized_mutation)
    assert_equal "Auth.MissingSession", unauthorized_response.fetch("errors").first.dig("extensions", "code")
  end

  test "converted graphql query endpoints return data for each read surface" do
    login!

    assert_equal 1, graphql("query { analyticsDatabaseInsightsOverview }").dig("data", "analyticsDatabaseInsightsOverview", "kpiStats", "totalInvestors", "total")
    assert_equal "family_office", graphql("query { analyticsDatabaseInsightsDistributions }").dig("data", "analyticsDatabaseInsightsDistributions", "byType", 0, "label")
    assert_equal @admin.id, graphql("query { analyticsTeam }").dig("data", "analyticsTeam", 0, "userId")

    user_query = <<~GRAPHQL
      query($id: ID!) {
        user(id: $id)
      }
    GRAPHQL
    user_response = graphql(user_query, variables: { id: @admin.id })
    assert_equal "Ada", user_response.dig("data", "user", "userDetails", "firstName")

    investor_search_query = <<~GRAPHQL
      query($filter: JSON, $columnFilter: JSON) {
        investorSearch(page: 1, limit: 10, filter: $filter, columnFilter: $columnFilter)
      }
    GRAPHQL
    investor_search = graphql(
      investor_search_query,
      variables: {
        filter: {
          joinOperator: "and",
          filterList: {
            investorType: [
              { operator: "inArray", value: ["family_office"] }
            ],
            qualified: [
              { operator: "inArray", value: ["NotQualified"] }
            ]
          }
        }
      }
    )
    assert_equal @investor.id, investor_search.dig("data", "investorSearch", "data", 0, "id")

    export_by_filters_query = <<~GRAPHQL
      query($columns: [String!], $filter: JSON, $columnFilter: JSON) {
        exportInvestorsByFilters(columns: $columns, filter: $filter, columnFilter: $columnFilter)
      }
    GRAPHQL
    export_by_filters = graphql(
      export_by_filters_query,
      variables: {
        columns: ["name", "websiteUrl"],
        filter: {
          joinOperator: "and",
          filterList: {
            investorType: [
              { operator: "inArray", value: ["family_office"] }
            ]
          }
        },
        columnFilter: {
          organization: [@organization.id]
        }
      }
    )
    assert_includes export_by_filters.dig("data", "exportInvestorsByFilters"), "Alpha Capital"

    export_by_ids_query = <<~GRAPHQL
      query($selectedIds: [ID!], $columns: [String!]) {
        exportInvestorsByIds(selectedIds: $selectedIds, columns: $columns)
      }
    GRAPHQL
    export_by_ids = graphql(
      export_by_ids_query,
      variables: {
        selectedIds: [@investor.id],
        columns: ["name"]
      }
    )
    assert_includes export_by_ids.dig("data", "exportInvestorsByIds"), "Alpha Capital"

    investor_query = <<~GRAPHQL
      query($id: ID!) {
        investor(id: $id)
      }
    GRAPHQL
    investor_response = graphql(investor_query, variables: { id: @investor.id })
    assert_equal "Alpha Fund I", investor_response.dig("data", "investor", "investmentVehicles", 0, "name")

    vehicle_query = <<~GRAPHQL
      query($id: ID!) {
        investmentVehicle(id: $id)
      }
    GRAPHQL
    vehicle_response = graphql(vehicle_query, variables: { id: @vehicle.id })
    assert_equal "Alpha Fund I", vehicle_response.dig("data", "investmentVehicle", "name")

    strategy_query = <<~GRAPHQL
      query($id: ID!) {
        investmentStrategy(id: $id)
      }
    GRAPHQL
    strategy_response = graphql(strategy_query, variables: { id: @strategy.id })
    assert_equal "Seed Strategy", strategy_response.dig("data", "investmentStrategy", "name")
    assert_equal @region.id, strategy_response.dig("data", "investmentStrategy", "regionInvestmentFocus", 0, "id")

    investor_contacts_query = <<~GRAPHQL
      query($investorId: ID!) {
        investorContacts(investorId: $investorId)
      }
    GRAPHQL
    investor_contacts = graphql(investor_contacts_query, variables: { investorId: @investor.id })
    assert_equal @contact.id, investor_contacts.dig("data", "investorContacts", "data", 0, "id")

    investment_entities_query = <<~GRAPHQL
      query($investorId: ID!) {
        investmentEntities(investorId: $investorId)
      }
    GRAPHQL
    investment_entities = graphql(investment_entities_query, variables: { investorId: @investor.id })
    assert_equal @entity.id, investment_entities.dig("data", "investmentEntities", "data", 0, "id")

    assert_equal @region.id, graphql("query { regions }").dig("data", "regions", "data", 0, "id")

    countries_query = <<~GRAPHQL
      query($regionIds: [ID!]) {
        countries(regionIds: $regionIds)
      }
    GRAPHQL
    countries_response = graphql(countries_query, variables: { regionIds: [@region.id] })
    assert_equal @country.id, countries_response.dig("data", "countries", "data", 0, "id")

    cities_query = <<~GRAPHQL
      query($id: ID!) {
        citiesByCountry(id: $id)
      }
    GRAPHQL
    cities_response = graphql(cities_query, variables: { id: @country.id })
    assert_equal @city.id, cities_response.dig("data", "citiesByCountry", "data", 0, "id")

    assert_equal @organization.id, graphql("query { organizations }").dig("data", "organizations", "items", 0, "value")

    iips_query = <<~GRAPHQL
      query($organizationIds: [ID!]) {
        idealInvestorProfiles(organizationIds: $organizationIds)
      }
    GRAPHQL
    iips_response = graphql(iips_query, variables: { organizationIds: [@organization.id] })
    assert_equal @ideal_investor_profile.id, iips_response.dig("data", "idealInvestorProfiles", "data", 0, "id")

    proof_ledger_query = <<~GRAPHQL
      query {
        proofLedger(filter: { investorId: "#{@investor.id}" })
      }
    GRAPHQL
    proof_ledger_response = graphql(proof_ledger_query)
    assert_equal @proof_ledger.field_id, proof_ledger_response.dig("data", "proofLedger", "data", 0, "fieldId")

    proof_comments_query = <<~GRAPHQL
      query {
        proofLedgerComments(
          filter: { investorId: "#{@investor.id}" }
          fieldId: "#{@proof_comment.field_id}"
        )
      }
    GRAPHQL
    proof_comments_response = graphql(proof_comments_query)
    assert_equal @proof_comment.comment, proof_comments_response.dig("data", "proofLedgerComments", "data", 0, "comment")
  end

  test "converted graphql mutations cover the write endpoints end to end" do
    login!

    create_account_manager_mutation = <<~GRAPHQL
      mutation($email: String!, $firstName: String, $lastName: String) {
        createAccountManager(email: $email, firstName: $firstName, lastName: $lastName) {
          id
        }
      }
    GRAPHQL
    create_account_manager = graphql(
      create_account_manager_mutation,
      variables: {
        email: "am@example.com",
        firstName: "Casey",
        lastName: "Manager"
      }
    )
    account_manager_id = create_account_manager.dig("data", "createAccountManager", "id")
    assert account_manager_id.present?
    assert_equal "Casey", UserDetail.find(account_manager_id).first_name

    create_investor = graphql("mutation { createInvestor { id } }")
    created_investor_id = create_investor.dig("data", "createInvestor", "id")
    assert created_investor_id.present?

    update_investor_mutation = <<~GRAPHQL
      mutation($id: ID!, $investor: JSON) {
        updateInvestor(id: $id, investor: $investor) {
          success
        }
      }
    GRAPHQL
    update_investor = graphql(
      update_investor_mutation,
      variables: {
        id: created_investor_id,
        investor: { name: "Beta Capital", websiteUrl: "https://beta.example" }
      }
    )
    assert_equal true, update_investor.dig("data", "updateInvestor", "success")
    assert_equal "Beta Capital", Investor.find(created_investor_id).name

    qualify_investor_mutation = <<~GRAPHQL
      mutation {
        qualifyInvestor(id: "#{created_investor_id}", qualified: true) {
          success
        }
      }
    GRAPHQL
    qualify_investor = graphql(qualify_investor_mutation)
    assert_equal true, qualify_investor.dig("data", "qualifyInvestor", "success")
    assert_equal true, Investor.find(created_investor_id).qualified

    create_vehicle_mutation = <<~GRAPHQL
      mutation($investorId: ID!, $name: String) {
        createInvestmentVehicle(investorId: $investorId, name: $name) {
          id
        }
      }
    GRAPHQL
    create_vehicle = graphql(
      create_vehicle_mutation,
      variables: {
        investorId: created_investor_id,
        name: "Beta Vehicle"
      }
    )
    created_vehicle_id = create_vehicle.dig("data", "createInvestmentVehicle", "id")
    assert created_vehicle_id.present?

    update_vehicle_mutation = <<~GRAPHQL
      mutation($id: ID!, $investmentVehicle: JSON) {
        updateInvestmentVehicle(id: $id, investmentVehicle: $investmentVehicle) {
          success
        }
      }
    GRAPHQL
    update_vehicle = graphql(
      update_vehicle_mutation,
      variables: {
        id: created_vehicle_id,
        investmentVehicle: { name: "Beta Vehicle II", type: "fund" }
      }
    )
    assert_equal true, update_vehicle.dig("data", "updateInvestmentVehicle", "success")
    assert_equal "Beta Vehicle II", InvestmentVehicle.find(created_vehicle_id).name

    create_strategy_mutation = <<~GRAPHQL
      mutation($investorId: ID!, $name: String) {
        createInvestmentStrategy(investorId: $investorId, name: $name) {
          id
        }
      }
    GRAPHQL
    create_strategy = graphql(
      create_strategy_mutation,
      variables: {
        investorId: created_investor_id,
        name: "Beta Strategy"
      }
    )
    created_strategy_id = create_strategy.dig("data", "createInvestmentStrategy", "id")
    assert created_strategy_id.present?

    update_strategy_mutation = <<~GRAPHQL
      mutation($id: ID!, $investmentStrategy: JSON) {
        updateInvestmentStrategy(id: $id, investmentStrategy: $investmentStrategy) {
          success
        }
      }
    GRAPHQL
    update_strategy = graphql(
      update_strategy_mutation,
      variables: {
        id: created_strategy_id,
        investmentStrategy: {
          name: "Beta Growth Strategy",
          regionInvestmentFocus: [@region.id],
          countryInvestmentFocus: [@country.id]
        }
      }
    )
    assert_equal true, update_strategy.dig("data", "updateInvestmentStrategy", "success")
    assert_equal "Beta Growth Strategy", InvestmentStrategy.find(created_strategy_id).name

    create_contact_mutation = <<~GRAPHQL
      mutation($investorId: ID!) {
        createInvestorContact(investorId: $investorId) {
          id
        }
      }
    GRAPHQL
    create_contact = graphql(create_contact_mutation, variables: { investorId: created_investor_id })
    created_contact_id = create_contact.dig("data", "createInvestorContact", "id")
    assert created_contact_id.present?

    update_contact_mutation = <<~GRAPHQL
      mutation($id: ID!, $investorContact: JSON) {
        updateInvestorContact(id: $id, investorContact: $investorContact) {
          success
        }
      }
    GRAPHQL
    update_contact = graphql(
      update_contact_mutation,
      variables: {
        id: created_contact_id,
        investorContact: {
          firstName: "Morgan",
          lastName: "Lee",
          email: "morgan@example.com"
        }
      }
    )
    assert_equal true, update_contact.dig("data", "updateInvestorContact", "success")
    assert_equal "Morgan", InvestorContact.find(created_contact_id).first_name

    create_entity_mutation = <<~GRAPHQL
      mutation($investmentVehicleId: ID!) {
        createInvestmentEntity(investmentVehicleId: $investmentVehicleId) {
          id
        }
      }
    GRAPHQL
    create_entity = graphql(create_entity_mutation, variables: { investmentVehicleId: created_vehicle_id })
    created_entity_id = create_entity.dig("data", "createInvestmentEntity", "id")
    assert created_entity_id.present?

    update_entity_mutation = <<~GRAPHQL
      mutation($id: ID!, $investmentEntity: JSON) {
        updateInvestmentEntity(id: $id, investmentEntity: $investmentEntity) {
          success
        }
      }
    GRAPHQL
    update_entity = graphql(
      update_entity_mutation,
      variables: {
        id: created_entity_id,
        investmentEntity: {
          name: "Beta SPV",
          type: "company"
        }
      }
    )
    assert_equal true, update_entity.dig("data", "updateInvestmentEntity", "success")
    assert_equal "Beta SPV", InvestmentEntity.find(created_entity_id).name

    create_proof_comment_mutation = <<~GRAPHQL
      mutation {
        createProofLedgerComment(
          filter: { investorId: "#{created_investor_id}" }
          fieldId: "status"
          comment: "Verified in GraphQL"
        ) {
          id
        }
      }
    GRAPHQL
    create_proof_comment = graphql(create_proof_comment_mutation)
    proof_comment_id = create_proof_comment.dig("data", "createProofLedgerComment", "id")
    assert proof_comment_id.present?

    delete_contact_mutation = <<~GRAPHQL
      mutation($id: ID!) {
        deleteInvestorContact(id: $id) {
          success
        }
      }
    GRAPHQL
    delete_contact = graphql(delete_contact_mutation, variables: { id: created_contact_id })
    assert_equal true, delete_contact.dig("data", "deleteInvestorContact", "success")
    assert_nil InvestorContact.find_by(id: created_contact_id)

    delete_entity_mutation = <<~GRAPHQL
      mutation($id: ID!) {
        deleteInvestmentEntity(id: $id) {
          success
        }
      }
    GRAPHQL
    delete_entity = graphql(delete_entity_mutation, variables: { id: created_entity_id })
    assert_equal true, delete_entity.dig("data", "deleteInvestmentEntity", "success")
    assert_nil InvestmentEntity.find_by(id: created_entity_id)
  end

  private

  def login!
    login_mutation = <<~GRAPHQL
      mutation($email: String!, $password: String!) {
        login(email: $email, password: $password) {
          authenticated
          userId
          roles
        }
      }
    GRAPHQL
    response = graphql(
      login_mutation,
      variables: {
        email: "admin@example.com",
        password: "Password123!"
      }
    )

    assert_equal true, response.dig("data", "login", "authenticated")
    assert_equal @admin.id, response.dig("data", "login", "userId")
  end

  def graphql(query, variables: nil)
    post "/graphql", params: {
      query: query,
      variables: variables
    }

    assert_response :success
    JSON.parse(response.body)
  end
end
