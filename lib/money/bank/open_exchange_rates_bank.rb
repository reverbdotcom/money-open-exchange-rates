require 'open-uri'
require 'money'
require 'json'
require File.expand_path('../../../open_exchange_rates_bank/version', __FILE__)

# Money gem class
class Money
  # https://github.com/RubyMoney/money#exchange-rate-stores
  module Bank
    # Invalid cache, file not found or cache empty
    class InvalidCache < StandardError; end

    # APP_ID not set error
    class NoAppId < StandardError; end

    # OpenExchangeRatesBank base class
    class OpenExchangeRatesBank < Money::Bank::VariableExchange
      VERSION = ::OpenExchangeRatesBank::VERSION
      # OpenExchangeRates urls
      OER_URL = 'http://openexchangerates.org/latest.json'
      OER_HISTORICAL_URL = 'http://openexchangerates.org/historical/%s.json'
      # OpenExchangeRates secure url
      SECURE_OER_URL = OER_URL.gsub('http:', 'https:')
      SECURE_OER_HISTORICAL_URL = OER_URL.gsub('http:', 'https:')

      BASE_CURRENCY = "USD"

      # use https to fetch rates from Open Exchange Rates
      # disabled by default to support free-tier users
      attr_accessor :secure_connection

      # As of the end of August 2012 all requests to the Open Exchange Rates
      # API must have a valid app_id
      attr_accessor :app_id

      # Cache accessor, can be a String or a Proc
      attr_accessor :cache

      # Date for historical api
      # see https://openexchangerates.org/documentation#historical-data
      attr_accessor :date

      # Rates expiration Time
      attr_reader :rates_expiration

      # Parsed OpenExchangeRates result as Hash
      attr_reader :oer_rates

      # Seconds after than the current rates are automatically expired
      attr_reader :ttl_in_seconds

      # Set the seconds after than the current rates are automatically expired
      # by default, they never expire.
      #
      # @example
      #   ttl_in_seconds = 86400 # will expire the rates in one day
      #
      # @param value [Integer] Time to live in seconds
      #
      # @return [Integer] Setted time to live in seconds
      def ttl_in_seconds=(value)
        @ttl_in_seconds = value
        refresh_rates_expiration if ttl_in_seconds
        @ttl_in_seconds
      end

      # Update all rates from openexchangerates JSON
      # @return [Array] Array of exchange rates
      def update_rates
        exchange_rates.each do |exchange_rate|
          rate = exchange_rate.last
          currency = exchange_rate.first
          next unless Money::Currency.find(currency)
          set_rate(BASE_CURRENCY, currency, rate)
          set_rate(currency, BASE_CURRENCY, 1.0 / rate)
        end
      end

      # Save rates on cache
      # Can raise InvalidCache
      #
      # @return [Proc,File]
      def save_rates
        fail InvalidCache unless cache
        text = read_from_url
        store_in_cache(text) if valid_rates?(text)
      rescue Errno::ENOENT
        raise InvalidCache
      end

      # Override Money `get_rate` method for caching
      # @param [String] from_currency Currency ISO code. ex. 'USD'
      # @param [String] to_currency Currency ISO code. ex. 'CAD'
      #
      # @return [Numeric] rate.
      def get_rate(from_currency, to_currency, opts = {})
        expire_rates

        if [from_currency, to_currency].include?(BASE_CURRENCY)
          super
        else
          1.0 * super(from_currency, BASE_CURRENCY) * super(BASE_CURRENCY, to_currency)
        end
      end

      # Expire rates when expired
      def expire_rates
        return unless ttl_in_seconds
        return if rates_expiration > Time.now
        update_rates
        refresh_rates_expiration
      end

      # Source url of openexchangerates
      # defined with app_id and secure_connection
      # @return [String] URL
      def source_url
        "#{oer_url}?app_id=#{app_id}"
      end

      protected

      # Latest url if no date given
      # @return [String] URL
      def oer_url
        if date
          historical_url
        else
          latest_url
        end
      end

      # Historical url generated from `date` attr_accessor
      # @return [String] URL
      def historical_url
        url = OER_HISTORICAL_URL
        url = SECURE_OER_HISTORICAL_URL if secure_connection
        url % date
      end

      # Latest url
      # @return [String] URL
      def latest_url
        return SECURE_OER_URL if secure_connection
        OER_URL
      end

      # Store the provided text data by calling the proc method provided
      # for the cache, or write to the cache file.
      #
      # @example
      #   store_in_cache("{\"rates\": {\"AED\": 3.67304}}")
      #
      # @param text [String] String to cache
      # @return [String,Integer]
      def store_in_cache(text)
        if cache.is_a?(Proc)
          cache.call(text)
        elsif cache.is_a?(String)
          open(cache, 'w') do |f|
            f.write(text)
          end
        end
      end

      # Read from cache when exist
      def read_from_cache
        if cache.is_a?(Proc)
          cache.call(nil)
        elsif cache.is_a?(String) && File.exist?(cache)
          open(cache).read
        end
      end

      # Read from url
      # @return [String] JSON content
      def read_from_url
        fail NoAppId if app_id.nil? || app_id.empty?
        open(source_url).read
      end

      # Check validity of rates response only for store in cache
      #
      # @example
      #   valid_rates?("{\"rates\": {\"AED\": 3.67304}}")
      #
      # @param [String] text is JSON content
      # @return [Boolean] valid or not
      def valid_rates?(text)
        parsed = JSON.parse(text)
        parsed && parsed.key?('rates')
      rescue JSON::ParserError
        false
      end

      # Get expire rates, first from cache and then from url
      # @return [Hash] key is country code (ISO 3166-1 alpha-3) value Float
      def exchange_rates
        doc = JSON.parse(read_from_cache || read_from_url)
        @oer_rates = doc['rates']
      end

      # Refresh expiration from now
      # return [Time] new expiration time
      def refresh_rates_expiration
        @rates_expiration = Time.now + ttl_in_seconds
      end
    end
  end
end
