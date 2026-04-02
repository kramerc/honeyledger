class ImportRulesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_import_rule, only: %i[ edit update destroy preview ]

  def index
    @import_rules = current_user.import_rules.includes(:account).order(priority: :desc, match_pattern: :asc)
  end

  def new
    @import_rule = current_user.import_rules.build
  end

  def create
    @import_rule = current_user.import_rules.build(import_rule_params)

    respond_to do |format|
      if @import_rule.save
        format.html { redirect_to import_rules_path, notice: "Rule was successfully created." }
        format.json { render json: @import_rule, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @import_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      if @import_rule.update(import_rule_params)
        format.html { redirect_to import_rules_path, notice: "Rule was successfully updated.", status: :see_other }
        format.json { render json: @import_rule, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @import_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @import_rule.destroy!

    respond_to do |format|
      format.html { redirect_to import_rules_path, notice: "Rule was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def preview_apply
    service = ImportRule::RetroactiveApply.new(user: current_user)
    @changes = service.preview
  end

  def apply
    service = ImportRule::RetroactiveApply.new(user: current_user)
    count = service.apply

    if service.errors.any?
      redirect_to preview_apply_import_rules_path, alert: service.errors.first
    else
      redirect_to import_rules_path, notice: "#{count} #{"transaction".pluralize(count)} reassigned."
    end
  end

  def preview
    service = ImportRule::RetroactiveApply.new(user: current_user, rule: @import_rule)
    @changes = service.preview
  end

  private

    def set_import_rule
      @import_rule = current_user.import_rules.find(params.expect(:id))
    end

    def import_rule_params
      params.expect(import_rule: [ :match_pattern, :match_type, :account_id, :priority ])
    end
end
