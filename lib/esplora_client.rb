# HTTParty wrapper for an Esplora REST API (mempool.space, Blockstream, or a
# self-hosted instance). Keyless: the base URL is the only configuration.
#
# Responses are normalized into plain hashes with amounts in satoshis, so the
# wallet scanner does not depend on this provider's field names:
#
#   { txid:, fee:, block_height:, block_time:, confirmed:,
#     inputs:  [{ address:, value: }], outputs: [{ address:, value: }] }
class EsploraClient
  include HTTParty

  class Error < StandardError; end
  class RateLimitedError < Error; end

  default_timeout 30

  # Public explorers throttle bursts: scanning a fresh extended key makes ~40
  # address lookups back to back, and mempool.space answers 429 well before
  # that. Requests are paced, and a 429 is retried with backoff (honouring
  # Retry-After) before giving up.
  MIN_INTERVAL = 0.5
  MAX_RETRIES = 4
  MAX_BACKOFF = 30
  CHAIN_PAGE_SIZE = 25

  TRANSPORT_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, Timeout::Error, IOError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT,
    OpenSSL::SSL::SSLError, JSON::ParserError, HTTParty::Error
  ].freeze

  def initialize(base_url:, min_interval: MIN_INTERVAL, sleeper: ->(seconds) { sleep(seconds) })
    @base_url = base_url.to_s.chomp("/")
    @min_interval = min_interval
    @sleeper = sleeper
    @last_request_at = nil
  end

  # Address usage stats: { tx_count:, funded:, spent: } across confirmed and
  # mempool activity. tx_count > 0 marks an address as used for the gap limit.
  def address_stats(address)
    body = get("/address/#{address}", expect: Hash)
    chain = body.fetch("chain_stats", {})
    mempool = body.fetch("mempool_stats", {})

    {
      tx_count: chain["tx_count"].to_i + mempool["tx_count"].to_i,
      funded: chain["funded_txo_sum"].to_i,
      spent: chain["spent_txo_sum"].to_i
    }
  end

  # Every confirmed transaction touching the address, newest first. Pages with
  # /txs/chain/:last_seen_txid; Esplora serves CHAIN_PAGE_SIZE per page, so a
  # shorter page is the last one.
  def address_transactions(address)
    transactions = []
    last_seen_txid = nil

    loop do
      path = "/address/#{address}/txs/chain"
      path += "/#{last_seen_txid}" if last_seen_txid
      page = get(path, expect: Array)
      break if page.empty?
      raise Error, "The explorer at #{@base_url} returned an unexpected transaction list" unless page.all?(Hash)

      transactions.concat(page.map { |raw_transaction| normalize_transaction(raw_transaction) })
      next_txid = page.last["txid"]
      break if page.size < CHAIN_PAGE_SIZE || next_txid == last_seen_txid

      last_seen_txid = next_txid
    end

    transactions
  end

  private

    # Every failure surfaces as EsploraClient::Error, so the refresh job can
    # record it on the wallet instead of crashing.
    def get(path, expect:)
      attempt = 0
      begin
        response = paced { self.class.get("#{@base_url}#{path}", headers: { "Accept" => "application/json" }) }
        handle_errors!(response)
        parsed = response.parsed_response
        unless parsed.is_a?(expect)
          raise Error, "The explorer at #{@base_url} did not return JSON; check that ESPLORA_URL points at an Esplora API"
        end

        parsed
      rescue RateLimitedError
        attempt += 1
        raise if attempt > MAX_RETRIES

        @sleeper.call(backoff(response, attempt))
        retry
      end
    rescue *TRANSPORT_ERRORS => e
      raise Error, "Could not reach the explorer at #{@base_url} (#{e.class.name.demodulize})"
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

    # Retry-After seconds when the server sends them, else 2, 4, 8, 16 seconds.
    def backoff(response, attempt)
      retry_after = response&.headers&.[]("retry-after").to_s
      seconds = retry_after.match?(/\A\d+\z/) ? retry_after.to_i : 2**attempt
      seconds.clamp(1, MAX_BACKOFF)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def handle_errors!(response)
      case response.code
      when 200..299
        # OK
      when 429
        raise RateLimitedError, "Rate limited by #{@base_url}; try again later"
      else
        # The body is logged, not shown: error text belongs to the operator.
        Rails.logger.warn("Esplora #{response.code} from #{@base_url}: #{response.body.to_s.strip.first(200)}")
        raise Error, "The explorer returned HTTP #{response.code}"
      end
    end

    def normalize_transaction(raw_transaction)
      status = raw_transaction["status"] || {}
      {
        txid: raw_transaction["txid"],
        fee: raw_transaction["fee"].to_i,
        block_height: status["block_height"],
        block_time: status["block_time"] && Time.zone.at(status["block_time"]),
        confirmed: status["confirmed"] == true,
        inputs: Array(raw_transaction["vin"]).map do |input|
          prevout = input["prevout"] || {}
          { address: prevout["scriptpubkey_address"], value: prevout["value"].to_i }
        end,
        outputs: Array(raw_transaction["vout"]).map do |output|
          { address: output["scriptpubkey_address"], value: output["value"].to_i }
        end
      }
    end
end
