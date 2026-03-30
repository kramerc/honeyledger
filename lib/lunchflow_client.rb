class LunchflowClient
  include HTTParty
  base_uri "https://lunchflow.app/api/v1"

  def initialize(api_key:)
    @api_key = api_key
  end

  def accounts
    response = self.class.get("/accounts", headers: auth_headers)
    handle_errors!(response)
    response["accounts"]
  end

  def transactions(account_id, include_pending: false)
    response = self.class.get("/accounts/#{account_id}/transactions", headers: auth_headers, query: {
      include_pending: include_pending
    }.compact)
    handle_errors!(response)
    response["transactions"]
  end

  def balance(account_id)
    response = self.class.get("/accounts/#{account_id}/balance", headers: auth_headers)
    handle_errors!(response)
    response["balance"]
  end

  private

  def auth_headers
    { "x-api-key" => @api_key }
  end

  def handle_errors!(response)
    case response.code
    when 401, 403
      raise UnauthorizedError, response["message"] || "Unauthorized"
    when 200..299
      # OK
    else
      raise Error, response["message"] || "API error (#{response.code})"
    end
  end

  class Error < StandardError; end
  class UnauthorizedError < Error; end
end
