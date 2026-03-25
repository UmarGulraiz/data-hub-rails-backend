module Types
  class MutationType < Types::BaseObject
    field :login, mutation: Mutations::Login
    field :logout, mutation: Mutations::Logout
    field :create_account_manager, mutation: Mutations::CreateAccountManager
    field :create_investor, mutation: Mutations::CreateInvestor
    field :update_investor, mutation: Mutations::UpdateInvestor
    field :qualify_investor, mutation: Mutations::QualifyInvestor
    field :create_investment_vehicle, mutation: Mutations::CreateInvestmentVehicle
    field :update_investment_vehicle, mutation: Mutations::UpdateInvestmentVehicle
    field :create_investment_strategy, mutation: Mutations::CreateInvestmentStrategy
    field :update_investment_strategy, mutation: Mutations::UpdateInvestmentStrategy
    field :create_investor_contact, mutation: Mutations::CreateInvestorContact
    field :update_investor_contact, mutation: Mutations::UpdateInvestorContact
    field :delete_investor_contact, mutation: Mutations::DeleteInvestorContact
    field :create_investment_entity, mutation: Mutations::CreateInvestmentEntity
    field :update_investment_entity, mutation: Mutations::UpdateInvestmentEntity
    field :delete_investment_entity, mutation: Mutations::DeleteInvestmentEntity
    field :update_proof_ledger, mutation: Mutations::UpdateProofLedger
    field :delete_proof_ledger, mutation: Mutations::DeleteProofLedger
    field :create_proof_ledger_comment, mutation: Mutations::CreateProofLedgerComment
  end
end
