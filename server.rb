require 'json'
require 'erb'

require_relative 'client'

module Hydrus
  class TaggingServer
    def initialize(config_file, state_file)
      @config = JSON.parse(File.read(config_file))
      @state  = Marshal.load(File.binread(state_file)) rescue {}

      @state_file = state_file

      @hydrus = Client.new(
        @config['server']['url'],
        @config['server']['key']
      )
    end

    attr_reader :state
    def client; @hydrus; end

    def call(env)
      req = Rack::Request.new(env)
      ctl = Controller.new(self, req)
      catch :done do
        ctl.process
      end
      ctl.finish
    end

    def save_state!
      File.binwrite(@state_file, Marshal.dump(@state))
    end

    class Controller
      ROUTES = [
        ['/', :GET, :index],
        ['/state', :POST, :load_state],

        ['/galleries/artist/:pixiv_id', :GET, :image_load_batch],
        ['/galleries/thumbnail/:hash', :GET, :image_fetch_thumbnail],
        ['/galleries/full/:hash', :GET, :image_fetch_full],
        ['/galleries/op/:hash', :DELETE, :image_delete],
        ['/galleries/op', :POST, :image_batch_modify],

        ['/tags', :POST, :tag_autocomplete],
      ].sort_by do |config|
        [config[0].count(':'), config[0].count('/'), config[0]]
      end.freeze

      def initialize(app, req)
        @app = app
        @req = req
        @res = Rack::Response.new

        @res.content_type = 'text/html'
        @res.status = 200
      end

      def finish
        @res.body.clear if @req.request_method == 'HEAD'
        @res.finish
      end

      def process
        route = nil
        params = {}
        input = @req.path.split('/').reject(&:empty?)
        ROUTES.find do |route_config|
          raw_path, verb, method = route_config
          fragments = raw_path.split('/').reject(&:empty?)
          case @req.request_method
          when 'HEAD'
            next if 'GET' != verb.to_s
          else
            next if @req.request_method != verb.to_s
          end
          next if input.size != fragments.size
          next unless fragments.each_with_index.all? do |k, i|
                 next true if k[0] == ':'
                 k == input[i]
               end
          param_indices = fragments.each_with_index.select do |k, i|
            k[0] == ':'
          end.map(&:last)
          params.clear
          param_indices.each do |i|
            params[fragments[i][1..-1]] = input[i]
          end
          true
        end&.tap do |config|
          route = config
        end

        if route.nil? then
          interrupt(404, '<h1>Page Not Found</h1>')
        end

        params.each do |k, v|
          @req.update_param k, v
        end

        interrupt(503, "Endpoint not ready.") unless respond_to? "route_#{route[2]}"
        send("route_#{route[2]}")
      rescue Exception => e
        $stderr.puts "#{e.class}: #{e.message}"
        $stderr.puts e.backtrace.first(10)
        $stderr.puts "  -> #{e.response.body}" if e.respond_to?(:response)
        interrupt(500, "Internal Server Error.")
      end

      def interrupt(code, msg)
        @res.content_type = 'text/html'
        @res.status = code
        @res.write msg
        throw :done, @res
      end

      def json(code, obj)
        @res.content_type = 'application/json'
        @res.status = code
        @res.write JSON.dump(obj)
        throw :done, @res
      end

      def route_index
        interrupt(200, PageLookup.render('index'))
      end

      def route_load_state
        case @req.content_type
        when 'application/json'
          state_data = JSON.parse(@req.body.read)
          state_data['user_images'].sort_by do |k, v|
            k != 'deleted' ? v.first : v.first + 1_000_000_000
          end.tap do |ordered_map|
            map = ordered_map.to_h
            map.transform_keys! &:to_i
            state_data['user_images'].replace({
              'keys' => map.keys,
              'values' => map.values,
            })
          end
          @app.state.replace state_data
          @app.save_state!
          json(200, state_data)
        else
          json(200, @app.state)
        end
      end

      def route_image_load_batch
        artist_id = @req.params['pixiv_id'].to_i
        order_id  = @app.state.dig('user_images', 'keys').index(artist_id)
        pixiv_ids = @app.state.dig('user_images', 'values').at(order_id)
        batch_output = normalize_hydrus_metadata(*pixiv_ids)
        if batch_output.empty? then
          @app.state['user_images']['keys'].delete_at(order_id)
          @app.state['user_images']['values'].delete_at(order_id)
          @app.save_state!
        end

        json(200, batch_output)
      end

      def route_image_fetch_thumbnail
        out = @app.client.query_get_file_thumbnail(hash: @req.params['hash'])
        _, mime, _, content = out.split(/[:;,]/, 4)
        @res.content_type = mime
        @res.status = 200
        @res.write content.unpack1('m*')
      rescue Net::HTTPExceptions => e
        $stderr.puts e.response.body
        interrupt(e.data.code, e.response.message)
      end

      def route_image_fetch_full
        out = @app.client.query_get_file_content(hash: @req.params['hash'])
        _, mime, _, content = out.split(/[:;,]/, 4)
        @res.content_type = mime
        @res.status = 200
        @res.write content.unpack1('m*')
      rescue Net::HTTPExceptions => e
        $stderr.puts e.response.body
        interrupt(e.data.code, e.response.message)
      end

      def route_image_batch_modify
        batch_data = JSON.parse(@req.body.read)
        
        if !batch_data['deletion'].nil? then
          short_reasons = {
            'censor' => 'Blatant Censors',
            'crop' => 'Crop',
            'paywall' => '"Please visit support website!"',
            'no reason' => nil,
          }
          @app.client.file_mark_delete(hashes: batch_data['hashes'], reason: short_reasons[batch_data['deletion']])
        else
          case batch_data['state']
          when 'inbox'
            @app.client.file_mark_unarchive(hashes: batch_data['hashes'])
          when 'archive'
            @app.client.file_mark_archive(hashes: batch_data['hashes'])
          end
        end

        unless batch_data['tags'].values.all? &:empty? then
          @app.client.tag_complex_build(hashes: batch_data['hashes']) do
            add_tag *batch_data['tags']['add']
            remove_tag *batch_data['tags']['delete']
          end
        end

        artist_id = batch_data['pixiv_id']
        order_id  = @app.state.dig('user_images', 'keys').index(artist_id)
        pixiv_ids = @app.state.dig('user_images', 'values').at(order_id)
        batch_output = normalize_hydrus_metadata(*pixiv_ids)
        if batch_output.empty? then
          @app.state['user_images']['keys'].delete_at(order_id)
          @app.state['user_images']['values'].delete_at(order_id)
          @app.save_state!
        end

        json(200, batch_output)
      end

      def route_tag_autocomplete
        tag = @req.body.read
        json(200, @app.client.tag_search(tag))
      end

      def normalize_hydrus_metadata(*pixiv_ids)
        import_meta = pixiv_ids.map do |image_id|
          [
            image_id,
            @app.state['images'].find do |image_meta| image_meta['id'] == image_id end,
          ]
        end.to_h
        join_tags = pixiv_ids.map do |image_id|
          "set:pixiv-#{image_id}"
        end
        hydrus_raw_meta = @app.client.query_search_files(
          [join_tags],
          sort_ascending: true,
          output_level: :detailed,
        )
        output = []
        hydrus_raw_meta.each do |hi|
          is_in_tag = ->(key){
            hi.dig('service_keys_to_statuses_to_tags', '6c6f63616c2074616773', '0').find do |t|
              case key
              when Regexp
                key.match?(t)
              else
                key == t
              end
            end
          }
          image_pixiv_id = is_in_tag.call(/^set:pixiv-\d+$/).scan(/\d+/).first.to_i
          image_pixiv_page_id = is_in_tag.call(/^page:\d+$/).scan(/\d+/).first.to_i rescue -1

          norm = {}
          norm[:id] = hi['file_id']
          norm[:hash] = hi['hash']
          norm[:pixiv_id] = image_pixiv_id
          norm[:pixiv_page_id] = image_pixiv_page_id
          norm[:pixiv] = import_meta[image_pixiv_id]
          norm[:mime] = hi['mime']
          norm[:flags] = []
          norm[:flags] << (hi['is_inbox'] ? :inbox : :archived)
          norm[:flags] << :trash if hi['is_trashed']
          norm[:flags] << :tagme_lazy if is_in_tag['meta:low priority tagme']
          norm[:urls] = hi['known_urls']
          norm[:tags] = {
            raw: hi.dig('service_keys_to_statuses_to_tags', '6c6f63616c2074616773', '0'),
            display: hi.dig('service_keys_to_statuses_to_display_tags', '6c6f63616c2074616773', '0'),
          }
          
          output << norm
        end
        output.sort_by! do |norm|
          norm.values_at(:pixiv_id, :pixiv_page_id, :id)
        end

        output
      end
    end

    private_constant :Controller

    module PageLookup; end
    class << PageLookup
      class Scoped < Object
        def initialize(**variables)
          variables.each do |k, v|
            instance_variable_set(:"@#{k}", v)
          end
        end
        def get_binding
          binding
        end
      end

      private
      def directory
        File.expand_path('./pages', __dir__)
      end

      public
      def render(name, variables: {})
        erb_file = File.join(directory, "#{name}.html.erb")
        html_file = File.join(directory, "#{name}.html")

        if File.exists?(erb_file) then
          erb = ERB.new(File.read(erb_file), 0, '>')
          erb.result(
            Scoped.new(**variables).get_binding,
          )
        elsif File.exists?(html_file) then
          File.read(html_file)
        else
          fail ArgumentError, "File #{name} not found!"
        end
      end
    end
    private_constant :PageLookup
  end
end