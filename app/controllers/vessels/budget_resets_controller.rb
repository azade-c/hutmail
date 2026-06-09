class Vessels::BudgetResetsController < ApplicationController
  include VesselScoped

  def create
    @vessel.reset_budget!
    redirect_to vessel_path(@vessel), notice: "Budget remis à zéro — le crédit 7j est de nouveau disponible"
  end
end
