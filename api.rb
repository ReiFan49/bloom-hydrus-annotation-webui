require 'net/http'
require 'uri'

require 'cbor'

module Hydrus
  class SimpleAPI
    def initialize(key, url: nil, session: false)
      @url = url || 'http://localhost:45869'
      @key = key
      @temporary = session
    end
    def permanent?
      !@temporary
    end
    def key?
      !@key.nil?
    end
    def key=(value)
      @temporary = false
      @key = value
    end
    def session_key=(value)
      self.key = value 
      @temporary = true
    end
    def cbor?
      defined?(CBOR)
    end

    def open(&block)
      uri = URI(@url)
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.port == 443,
        connect_timeout: 120, read_timeout: 120,
      ) do |context|
        Scoped.new(self, context).instance_exec(&block)
      end
    end

    # server implementation only use get and post
    def get(endpoint, cbor: nil, context: nil, headers: nil, query: nil, body: nil)
      request :Get, endpoint,
        cbor: cbor,
        context: context, headers: headers, query: query,
        body: body
    end
    def post(endpoint, cbor: nil, context: nil, headers: nil, query: nil, body: nil)
      request :Post, endpoint,
        cbor: cbor,
        context: context, headers: headers, query: query,
        body: body
    end

    private
    def add_headers(req, cbor)
      if @temporary then
        req['Hydrus-Client-API-Session-Key'] = @key
      else
        req['Hydrus-Client-API-Access-Key'] = @key
      end

      if cbor then
        req.content_type = 'application/cbor'
        req['Accept'] = 'application/cbor'
      else
        req['Accept'] = 'application/json'
      end
    end

    def request(
      method,
      endpoint,
      cbor: nil,
      context: nil,
      headers: nil,
      query: nil,
      body: nil
    )
      use_cbor = cbor.nil? ? cbor? : !!cbor

      convert_values = ->(pair, &block) { pair[-1] = block.call(pair.last) }
      convert_enumerables = ->(value) {
        case value
        when Enumerable
        when TrueClass, FalseClass
        else
          return value
        end
        use_cbor ?
          [CBOR.dump(value)].pack('m0') :
          JSON.dump(value)
      }

      unless context.nil? then
        method = String(method).capitalize
        http_class = Net::HTTP.const_get(method)
        fail ArgumentError, "Invalid method #{method.upcase}" unless Class === http_class && http_class < Net::HTTPRequest

        case query
        when NilClass
          query = []
        when Hash
          query.transform_values! &convert_enumerables
          query = URI.decode_www_form(URI.encode_www_form(query))
        when Array
          query.each do |pair|
            convert_values.call(pair, &convert_enumerables)
          end
        end
        query.reject! do |pair| pair.first == 'cbor' end
        query << ['cbor', 1] if body.nil? && use_cbor

        uri = URI(@url)
        uri.path = endpoint
        uri.query = URI.encode_www_form(query)

        req = http_class.new(uri.request_uri)
        add_headers(req, use_cbor)
        headers&.each do |k, v|
          req[k] = v
        end
        case body
        when NilClass
          # noop
        when IO
          req.content_type = 'application/octet-stream'
          req.body = body.read
        when Hash
          req.content_type = 'application/json' unless use_cbor
          req.body = use_cbor ? CBOR.dump(body) : JSON.dump(body)
        else
          req.body = String(body)
        end

        res = context.request(req)
        res.value

        case res.content_type
        when 'application/cbor'
          return CBOR.load(res.body)
        when 'application/json'
          return JSON.parse(res.body)
        else
          return sprintf('data:%s;base64,%s', res.content_type, [res.body.b].pack('m0'))
        end
      end

      open do
        @client.send :request, method, endpoint, cbor: use_cbor, context: @context, headers: headers, query: query, body: body
      end
    end

    class Scoped
      METHOD_KEYS = %i(get post).freeze

      def initialize(client, context)
        @context = context
        @client  = client
      end

      def method_missing(meth, *args, &block)
        if METHOD_KEYS.include?(meth)
          return @client.public_send(meth, *args, context: @context, &block)
        end
        super
      end

      def respond_to_missing?(meth, priv = false)
        return true if METHOD_KEYS.include?(meth)
        super
      end
    end

    private_constant :Scoped
  end
end