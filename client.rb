require_relative 'api'
require_relative 'client_files'
require_relative 'client_tags'
require_relative 'client_queries'

module Hydrus
  class Client
    def initialize(url, key)
      @key = key
      @api = SimpleAPI.new(key, url: url, session: false)

      @permissions = []
      @service_keys = {}
      @services = {}
    end

    attr_reader :permissions, :service_keys, :services

    private
    def ensure_api_key!
      ensure_api_set!
      ensure_session_key
    end
    def ensure_api_set!
      return if @api.key?
      fail 'Access Key uninitialized.' if @key.nil? || @key.empty?
      @api.key = @key
    end
    def ensure_session_key
      if @api.permanent?
        @api.session_key = @api.get('/session_key').fetch('session_key', nil)
        unless @api.key?
          @api.key = @key
          fail 'Unable to fetch new session key.'
        end
      end

      refresh_permissions &&
        refresh_services
    end
    def refresh_permissions
      ensure_api_set!
      @permissions.replace
        @api.get('/verify_access_key').fetch('basic_permissions', []).to_a
      !@permissions.empty?
    end
    def refresh_services
      ensure_api_set!
      @services.clear
      @service_keys.clear
      @api.get('/get_services')&.each do |service_group, service_raw_list|
        service_map = service_raw_list.map(&:values).to_h
        @services.store service_group, service_map.values.map(&:b)
        @service_keys.update service_map.transform_values(&:b).invert
      end
      !@services.empty?
    end

    def validate_service(group, name: nil, key: nil)
      refresh_services if @services.empty?
      return if name.nil? && key.nil?
      fail KeyError, "group #{group} not exist" unless @services.key?(group)

      service_list = @services[group]

      nil.tap do
        fail KeyError, "key #{key} does not represent #{group}!" unless service_list.include?(key)
      end unless key.nil?
      nil.tap do
        key_detect = @service_keys.key(name)
        fail KeyError, "service #{name} not exist on this server!" if key_detect.nil?
        fail KeyError, "key #{key} does not represent #{group}!" unless service_list.include?(key_detect)
      end unless name.nil?

      nil
    end

    def raw_request(method, endpoint, cbor: nil, context: nil, headers: nil, query: nil, body: nil, file: nil)
      unless file.nil?
        fail TypeError, 'invalid IO provided' unless file.respond_to?(:read)
      end
      @api.send :request, method, endpoint,
        cbor: cbor, context: context,
        headers: headers, query: query,
        body: file.respond_to?(:read) ? file : body
    end
    def request(method, endpoint, cbor: nil, context: nil, headers: nil, query: nil, body: nil, file: nil)
      retries = 3
      catch :output do
        throw :output, raw_request(method, endpoint, cbor: cbor, context: context, headers: headers, query: query, body: body, file: file)
      rescue Net::HTTPExceptions => e
        fail e unless retries.positive?
        case e.data.code
        # when 401
        #   fail e unless e.response.body.include?('access key') ||
        #     e.response.body.include?('session key')
        when 419
          @api.key = @key
          # pass
        else
          fail e
        end
        ensure_api_key!
        retries -= 1
        retry
      end
    end

    public
    def default_tag_service
      refresh_services if @services.fetch('local_tags', []).empty?
      @services['local_tags'].first
    end
    def default_file_repository
      refresh_services if @services.fetch('local_files', []).empty?
      @services['local_files'].first
    end

    include ClientFiles
    include ClientTags
    include ClientQueries
  end
end