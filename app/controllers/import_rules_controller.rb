class ImportRulesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_import_rule, only: %i[ edit update destroy ]

  def index
    assign_rules
  end

  def new
    @import_rule = current_user.import_rules.build
  end

  def create
    attrs = import_rule_params
    @import_rule = current_user.import_rules.build(attrs)
    @import_rule.priority = next_priority if attrs[:priority].blank?

    respond_to do |format|
      if @import_rule.save
        notice = saved_notice("created", maybe_apply_retroactively)
        @selected_id = @import_rule.id
        assign_rules
        format.html { redirect_to import_rules_path, notice: notice }
        format.turbo_stream { flash.now[:notice] = notice; render :saved }
        format.json { render json: @import_rule, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: editor_stream(@import_rule), status: :unprocessable_entity }
        format.json { render json: @import_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      if @import_rule.update(import_rule_params)
        notice = saved_notice("updated", maybe_apply_retroactively)
        @selected_id = @import_rule.id
        assign_rules
        format.html { redirect_to import_rules_path, notice: notice, status: :see_other }
        format.turbo_stream { flash.now[:notice] = notice; render :saved }
        format.json { render json: @import_rule, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: editor_stream(@import_rule), status: :unprocessable_entity }
        format.json { render json: @import_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @import_rule.destroy!
    assign_rules

    respond_to do |format|
      format.html { redirect_to import_rules_path, notice: "Rule was successfully destroyed.", status: :see_other }
      format.turbo_stream { flash.now[:notice] = "Rule was successfully destroyed."; render :workbench_update }
      format.json { head :no_content }
    end
  end

  # Reassign priority from a dragged ordering (first id = highest priority).
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    rules = current_user.import_rules.where(id: ids).index_by(&:id)

    ImportRule.transaction do
      ids.each_with_index do |id, index|
        rule = rules[id]
        rule&.update_column(:priority, ids.size - index)
      end
    end

    head :no_content
  end

  # Live "matches in your ledger" panel for the editor (driven by the draft form values).
  def match_preview
    @preview = ImportRule::MatchPreview.new(
      user: current_user,
      pattern: params[:pattern],
      match_type: params[:match_type],
      account_id: params[:account_id],
      exclude: params[:exclude]
    )
    render partial: "match_preview", locals: { preview: @preview }
  end

  def preview_apply
    service = ImportRule::RetroactiveApply.new(user: current_user)
    @changes = service.preview
  end

  def apply
    service = ImportRule::RetroactiveApply.new(user: current_user)
    count = service.apply

    if service.errors.any?
      @apply_error = service.errors.first
      respond_to do |format|
        format.html { redirect_to preview_apply_import_rules_path, alert: @apply_error }
        format.turbo_stream { flash.now[:alert] = @apply_error; render :apply }
      end
    else
      assign_rules
      respond_to do |format|
        format.html { redirect_to import_rules_path, notice: "#{count} #{"transaction".pluralize(count)} updated." }
        format.turbo_stream { flash.now[:notice] = "#{count} #{"transaction".pluralize(count)} updated."; render :apply }
      end
    end
  end

  # Preview the impact of the draft rule in the editor (current form values), so Preview
  # works for a brand-new rule and reflects unsaved edits — not just the saved rule.
  def preview
    @import_rule = build_draft_rule
    @dirty = draft_dirty?
    @changes = ImportRule::RetroactiveApply.new(user: current_user, rule: @import_rule).preview
  end

  private

    # When the per-rule Preview's "Apply" submitted the editor form, also re-run the saved
    # rule over existing transactions. Returns the count updated, or nil if not applying;
    # records any apply failure in @apply_error so the notice can surface it.
    def maybe_apply_retroactively
      return nil if params[:apply_after_save].blank?

      service = ImportRule::RetroactiveApply.new(user: current_user, rule: @import_rule)
      applied = service.apply
      @apply_error = service.errors.first
      applied
    end

    def saved_notice(verb, applied)
      return "Rule was successfully #{verb}." if applied.nil?
      return "Rule saved, but the changes couldn’t be applied: #{@apply_error}" if @apply_error
      return "Rule saved." if applied.zero?

      "Rule saved · #{applied} #{"transaction".pluralize(applied)} updated."
    end

    # True when the draft has unsaved edits (or is a brand-new rule) — so the Preview modal
    # can tell the user that applying will also save the rule.
    def draft_dirty?
      saved = params[:id].present? ? current_user.import_rules.find_by(id: params[:id]) : nil
      return true if saved.nil?

      saved.match_pattern != @import_rule.match_pattern.to_s.strip ||
        saved.match_type != @import_rule.match_type ||
        saved.account_id != @import_rule.account_id ||
        saved.exclude? != @import_rule.exclude?
    end

    def build_draft_rule
      exclude = ActiveModel::Type::Boolean.new.cast(params[:exclude]) || false
      match_type = ImportRule.match_types.key?(params[:match_type].to_s) ? params[:match_type] : "contains"
      # Resolve the account through the current user so an enumerated foreign account_id can't
      # be referenced in the (un-validated) draft preview/apply.
      account = params[:account_id].present? ? current_user.accounts.find_by(id: params[:account_id]) : nil
      current_user.import_rules.build(
        match_pattern: params[:pattern],
        match_type: match_type,
        account: (exclude ? nil : account),
        exclude: exclude
      )
    end

    def assign_rules
      @import_rules = current_user.import_rules.includes(:account).order(priority: :desc, match_pattern: :asc).to_a
      @total_count = @import_rules.size
      @exclude_count = @import_rules.count(&:exclude?)
      @assign_count = @total_count - @exclude_count
    end

    # Re-render the editor frame with the (invalid) draft so its errors show inline.
    def editor_stream(rule)
      turbo_stream.replace("rule_editor", partial: "import_rules/form", locals: { import_rule: rule })
    end

    # New rules go to the top of the priority order (highest wins) unless a priority is given.
    def next_priority
      (current_user.import_rules.maximum(:priority) || -1) + 1
    end

    def set_import_rule
      @import_rule = current_user.import_rules.find(params.expect(:id))
    end

    def import_rule_params
      params.expect(import_rule: [ :match_pattern, :match_type, :account_id, :priority, :exclude ])
    end
end
