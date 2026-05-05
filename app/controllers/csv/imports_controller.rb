class Csv::ImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, except: :index
  before_action :set_csv_import, only: %i[ show update destroy confirm parse ]

  def index
    if params[:account_id].present?
      @account = current_user.accounts.real.find(params[:account_id])
      @csv_imports = @account.csv_imports.order(created_at: :desc)
    else
      @csv_imports = current_user.csv_imports.includes(:account).order(created_at: :desc)
    end
  end

  def new
    @csv_import = @account.csv_imports.new(user: current_user)
  end

  def create
    @csv_import = @account.csv_imports.new(
      user: current_user,
      column_mappings: Csv::Import.last_mapping_for(account: @account),
      state: "pending"
    )
    file_param = params.require(:csv_import)[:file]
    @csv_import.file.attach(file_param) if file_param.present?

    if @csv_import.save
      redirect_to account_csv_import_path(@account, @csv_import), notice: "CSV uploaded. Map the columns to continue."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @preview = build_preview
  end

  def update
    if @csv_import.update(state: "mapped", column_mappings: mapping_params, error: nil)
      redirect_to confirm_account_csv_import_path(@account, @csv_import),
                  notice: "Mapping saved. Review how the rows will import below, then click \"Parse and import\"."
    else
      @preview = build_preview
      render :show, status: :unprocessable_entity
    end
  end

  def confirm
    if @csv_import.pending? || @csv_import.column_mappings.blank?
      redirect_to account_csv_import_path(@account, @csv_import),
                  alert: "Save a column mapping before confirming."
      return
    end

    @preview = build_preview
  end

  def parse
    if @csv_import.column_mappings.blank? || @csv_import.pending?
      redirect_to account_csv_import_path(@account, @csv_import), alert: "Save a column mapping before parsing."
      return
    end

    Csv::ParseJob.perform_later(@csv_import.id)
    redirect_to account_csv_import_path(@account, @csv_import), notice: "Parse and import enqueued."
  end

  def destroy
    @csv_import.destroy!
    redirect_to account_csv_imports_path(@account), notice: "Import deleted.", status: :see_other
  end

  private

    def set_account
      @account = current_user.accounts.real.find(params[:account_id])
    end

    def set_csv_import
      @csv_import = @account.csv_imports.find(params[:id])
    end

    def mapping_params
      mapping = params.dig(:csv_import, :column_mappings)
      raw = mapping.respond_to?(:to_unsafe_h) ? mapping.to_unsafe_h : (mapping.is_a?(Hash) ? mapping.dup : {})
      raw["description_columns"] = Array(raw["description_columns"]).reject(&:blank?)
      raw["debit_values"] = split_csv_list(raw["debit_values"]) if raw.key?("debit_values")
      raw["skip_rows"] = raw["skip_rows"].to_i if raw["skip_rows"].present?
      raw["invert_amount"] = ActiveModel::Type::Boolean.new.cast(raw["invert_amount"]) if raw.key?("invert_amount")
      raw
    end

    def split_csv_list(value)
      return value if value.is_a?(Array)
      value.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def build_preview
      return nil unless @csv_import.file.attached?

      mappings = @csv_import.column_mappings.presence || {}
      currency = @account.currency

      raw = begin
        @csv_import.file.open { |io| Csv::Parser.raw_preview(io, limit: 10) }
      rescue Csv::Parser::Error, ::CSV::MalformedCSVError, ActiveStorage::Error
        { headers: [], rows: [] }
      end

      parsed_rows = []
      parse_error = nil
      if mappings_complete?(mappings)
        begin
          parsed = @csv_import.file.open { |io| Csv::Parser.preview(io, mappings: mappings, currency: currency, limit: 10) }
          parsed_rows = parsed[:rows]
        rescue Csv::Parser::Error, Csv::Parser::RowError => e
          parse_error = e.message
        end
      end

      {
        headers: raw[:headers],
        raw_rows: raw[:rows],
        parsed_rows: parsed_rows,
        error: parse_error
      }
    end

    def mappings_complete?(mappings)
      return false if mappings.blank?
      mappings = mappings.with_indifferent_access
      return false if mappings[:date_column].blank? || mappings[:amount_mode].blank?
      case mappings[:amount_mode]
      when "signed", "sign_indicator"
        mappings[:amount_column].present?
      when "debit_credit"
        mappings[:debit_column].present? && mappings[:credit_column].present?
      else
        false
      end
    end
end
