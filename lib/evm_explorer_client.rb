# HTTParty wrapper for an Etherscan-compatible EVM explorer API. Which provider
# it talks to is configuration, not code: both presets below serve the same
# `module=account&action=txlist` routes and differ only in the base URL, the
# name of the chain parameter, and the route for the chain tip.
#
# Blockscout's PRO API is the default. Its free key covers Ethereum, Arbitrum,
# Polygon, OP, and Base and returns the OP-stack L1 fee. Etherscan's free,
# Lite, and Standard plans are licensed for personal and research use only, a
# server that serves other people needs its commercial plan, and its free tier
# leaves out OP and Base. Pick it only when those terms fit.
#
# Responses are normalized into plain hashes with amounts in wei (Integer) and
# addresses lowercase, so the scanner does not depend on provider field names:
#
#   normal:   { hash:, from:, to:, value:, fee:, failed:, block_number:, timestamp:, contract_address: }
#   internal: { hash:, trace_id:, from:, to:, value:, failed:, block_number:, timestamp: }
#
# The API key travels as a query parameter, so no URL, query, or response body
# ever reaches an exception message; everything raised is EvmExplorerClient::Error.
class EvmExplorerClient
  include HTTParty

  class Error < StandardError; end
  class RateLimitedError < Error; end

  PROVIDERS = {
    "blockscout" => {
      base_url: "https://api.blockscout.com/v2/api",
      chain_param: "chain_id",
      tip: { module: "block", action: "eth_block_number" }
    },
    "etherscan" => {
      base_url: "https://api.etherscan.io/v2/api",
      chain_param: "chainid",
      tip: { module: "proxy", action: "eth_blockNumber" }
    }
  }.freeze

  ETHEREUM_MAINNET = 1

  default_timeout 30

  # Etherscan's free keys return at most 1,000 records per request; Blockscout
  # charges per request rather than per record, so a full page costs the same.
  PAGE_SIZE = 1_000
  # Etherscan's free tier allows 3 requests a second, Blockscout's 5.
  MIN_INTERVAL = 0.4
  MAX_RETRIES = 4
  MAX_BACKOFF = 30

  TRANSPORT_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, Timeout::Error, IOError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT,
    OpenSSL::SSL::SSLError, JSON::ParserError, HTTParty::Error
  ].freeze

  def initialize(provider:, api_key:, chain_id:, base_url: nil, min_interval: MIN_INTERVAL, sleeper: ->(seconds) { sleep(seconds) })
    @preset = PROVIDERS.fetch(provider.to_s) do
      raise Error, "Unknown EVM explorer #{provider.inspect}; set EVM_EXPLORER to one of #{PROVIDERS.keys.join(", ")}"
    end
    @provider = provider.to_s
    @api_key = api_key.to_s
    @chain_id = chain_id
    @base_url = (base_url.presence || @preset[:base_url]).to_s.chomp("/")
    @min_interval = min_interval
    @sleeper = sleeper
    @last_request_at = nil
  end

  # Every transaction the address sent or received, oldest first. A failed
  # (reverted) transaction moves no value but its sender still paid for gas.
  def normal_transactions(address)
    paginate("txlist", address, key: ->(entry) { entry[:hash] }) { |raw| normalize_normal(raw) }
  end

  # Value moved by contract calls inside a transaction, e.g. a DEX paying out
  # ETH. Incoming contract-initiated ETH appears only here, never in txlist.
  def internal_transactions(address)
    paginate("txlistinternal", address, key: ->(entry) { [ entry[:hash], entry[:trace_id] ] }) { |raw| normalize_internal(raw) }
  end

  # The chain tip's block number, for counting confirmations.
  def block_number
    body = get(@preset[:tip])
    result = body["result"]
    unless result.is_a?(String) && result.match?(/\A0x\h+\z/)
      raise Error, "The explorer returned an unexpected block number"
    end

    result.to_i(16)
  end

  private

    # Pages by block range rather than page number: Etherscan caps page × offset
    # at 10,000 records, so each request restarts from the last block seen and
    # the entries repeated from that block are dropped by key.
    def paginate(action, address, key:)
      entries = {}
      start_block = 0

      loop do
        page = records(get({ module: "account", action: action, address: address, startblock: start_block, sort: "asc", page: 1, offset: PAGE_SIZE }))
        normalized = page.map { |raw| yield(object(raw, "transaction")) }
        normalized.each { |entry| entries[key.call(entry)] ||= entry }
        break if page.size < PAGE_SIZE

        next_start = normalized.last[:block_number]
        # A whole page from one block would loop forever on the same request.
        raise Error, "The explorer returned more than #{PAGE_SIZE} records in a single block" if next_start == start_block

        start_block = next_start
      end

      entries.values
    end

    # The Etherscan envelope: status "1" with a result list, or status "0" with
    # a message ("No transactions found" is an empty list, not a failure).
    # Blockscout adds status "2" when it has not finished indexing internal
    # transactions for an old block range; what it returns is still correct, and
    # the next refresh fetches the rest.
    def records(body)
      result = body["result"]
      case body["status"].to_s
      when "1", "2"
        Rails.logger.warn("EVM explorer #{@provider}: #{body["message"].to_s.first(120)}") if body["status"].to_s == "2"
        raise Error, "The explorer returned an unexpected transaction list" unless result.is_a?(Array)

        result
      when "0"
        return [] if result.is_a?(Array) && result.empty?

        reject!(body)
      else
        raise Error, "The explorer did not return an Etherscan-style response; check EVM_EXPLORER and EVM_EXPLORER_URL"
      end
    end

    def reject!(body)
      text = [ body["message"], body["result"] ].grep(String).join(" ")
      raise RateLimitedError, "Rate limited by the explorer; try again later" if text.match?(/rate limit/i)
      raise Error, "The explorer rejected the API key; check EVM_EXPLORER_API_KEY" if text.match?(/api.?key/i)

      Rails.logger.warn("EVM explorer #{@provider} error: #{scrub(text).first(200)}")
      raise Error, "The explorer refused the request (#{scrub(body["message"].to_s).first(80)})"
    end

    def get(params)
      raise Error, "No EVM explorer API key is configured; set EVM_EXPLORER_API_KEY" if @api_key.blank?

      attempt = 0
      begin
        query = params.merge(@preset[:chain_param] => @chain_id, apikey: @api_key)
        response = paced { self.class.get(@base_url, query: query, headers: { "Accept" => "application/json" }) }
        handle_errors!(response)
        parsed = response.parsed_response
        raise Error, "The explorer did not return JSON; check EVM_EXPLORER_URL" unless parsed.is_a?(Hash)

        # Etherscan's JSON-RPC proxy reports a rate limit inside a 200 body.
        reject!(parsed) if parsed["status"].to_s == "0" && !parsed["result"].is_a?(Array)
        parsed
      rescue RateLimitedError
        attempt += 1
        raise if attempt > MAX_RETRIES

        @sleeper.call(backoff(response, attempt))
        retry
      end
    rescue *TRANSPORT_ERRORS => e
      raise Error, "Could not reach the EVM explorer (#{e.class.name.demodulize})"
    end

    def handle_errors!(response)
      case response.code
      when 200..299
        # OK
      when 429
        raise RateLimitedError, "Rate limited by the explorer; try again later"
      when 401, 402, 403
        # Blockscout answers 402 when no key or an exhausted key is sent.
        raise Error, "The explorer rejected the API key or its quota is used up (HTTP #{response.code}); check EVM_EXPLORER_API_KEY"
      else
        Rails.logger.warn("EVM explorer #{@provider} HTTP #{response.code}: #{scrub(response.body.to_s.strip).first(200)}")
        raise Error, "The explorer returned HTTP #{response.code}"
      end
    end

    def paced
      if @last_request_at && @min_interval.positive?
        wait = @min_interval - (monotonic_now - @last_request_at)
        @sleeper.call(wait) if wait.positive?
      end
      yield
    ensure
      @last_request_at = monotonic_now
    end

    def backoff(response, attempt)
      retry_after = response&.headers&.[]("retry-after").to_s
      seconds = retry_after.match?(/\A\d+\z/) ? retry_after.to_i : 2**attempt
      seconds.clamp(1, MAX_BACKOFF)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Provider text can echo the request; never let the key into a log line.
    def scrub(text)
      @api_key.present? ? text.gsub(@api_key, "[FILTERED]") : text
    end

    def normalize_normal(raw)
      {
        hash: transaction_hash(raw["hash"]),
        from: address(raw["from"]),
        to: address(raw["to"]),
        value: integer(raw["value"]),
        fee: integer(raw["gasUsed"]) * integer(raw["gasPrice"]),
        failed: raw["isError"].to_s == "1" || raw["txreceipt_status"].to_s == "0",
        block_number: integer(raw["blockNumber"]),
        timestamp: Time.zone.at(integer(raw["timeStamp"])),
        contract_address: address(raw["contractAddress"])
      }
    end

    # Etherscan names the hash "hash" and the trace "traceId"; Blockscout uses
    # "transactionHash" and "index". A contract creation has no "to"; the value
    # went to the created contract.
    def normalize_internal(raw)
      {
        hash: transaction_hash(raw["hash"].presence || raw["transactionHash"]),
        trace_id: (raw["traceId"].presence || raw["index"]).to_s,
        from: address(raw["from"]),
        to: address(raw["to"]) || address(raw["contractAddress"]),
        value: integer(raw["value"]),
        failed: raw["isError"].to_s == "1",
        block_number: integer(raw["blockNumber"]),
        timestamp: Time.zone.at(integer(raw["timeStamp"]))
      }
    end

    def object(value, field)
      raise Error, "The explorer returned a malformed #{field}" unless value.is_a?(Hash)

      value
    end

    def transaction_hash(value)
      raise Error, "The explorer returned a transaction without a hash" unless value.is_a?(String) && value.match?(/\A0x\h{64}\z/)

      value.downcase
    end

    # Amounts arrive as decimal strings (wei can exceed any float).
    def integer(value)
      return 0 if value.nil? || value == ""
      return value if value.is_a?(Integer)
      raise Error, "The explorer returned a non-numeric amount" unless value.is_a?(String) && value.match?(/\A\d+\z/)

      value.to_i
    end

    def address(value)
      return nil if value.nil? || value == ""
      raise Error, "The explorer returned a malformed address" unless value.is_a?(String) && value.match?(/\A0x\h{40}\z/)

      value.downcase
    end
end
