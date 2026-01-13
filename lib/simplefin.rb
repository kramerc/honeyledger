class Simplefin
  include HTTParty
  base_uri "https://beta-bridge.simplefin.org/simplefin"

  def initialize(url: nil, username: nil, password: nil)
    # Parse username and password out of URL if present
    if url
      uri = URI.parse(url)
      @auth = { username: uri.user, password: uri.password } if uri.user && uri.password
      base_url = "#{uri.scheme}://#{uri.host}#{uri.port && uri.port != URI::HTTP::DEFAULT_PORT && uri.port != URI::HTTPS::DEFAULT_PORT ? ":#{uri.port}" : ""}#{uri.path}"
      self.class.base_uri(base_url)
    elsif username && password
      @auth = { username: username, password: password }
    end
  end

  def info
    self.class.get("/info")
  end

  def claim(token)
    url = Base64.decode64(token)
    self.class.post(url)
  end

  def accounts(start_date: nil, end_date: nil, pending: false, account: nil, balances_only: false)
    raise UnauthorizedError, "Authentication required" unless @auth

    self.class.get("/accounts", basic_auth: @auth, query: {
      'start-date': start_date,
      'end-date': end_date,
      pending: pending ? 1 : 0,
      account: account,
      'balances-only': balances_only ? 1 : 0
    }.compact)
  end

  class UnauthorizedError < StandardError; end
end
