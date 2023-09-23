module Hydrus
  module ClientQueries
    QUERY_SORT = %i(
      size duration import_time
      type random
      width height ratio
      pixels tag_count view_count total_view_time
      bitrate audio
      mtime
      framerate frame_count
      last_view_time atime
      hash
    ).freeze

    QUERY_METADATA_DETAIL = %i(
      why
      basic
      detailed
      deep
    ).freeze

    def query_search_files_pointers(tags, file_service_name: nil, file_service_key: nil, tag_service_name: nil, tag_service_key: nil, sort_type: :import_time, sort_ascending: false, return_flag: [:ids], context: nil)
      validate_service 'local_files', name: file_service_name, key: file_service_key
      validate_service 'local_tags', name: tag_service_name, key: tag_service_key
      fail ArgumentError, "Return nothing." if return_flag.empty?

      query = {}
      query[:tags] = tags

      query[:file_service_name] = file_service_name
      query[:file_service_key] = file_service_key
      query[:tag_service_name] = tag_service_name
      query[:tag_service_key] = tag_service_key

      query[:file_sort_type] = QUERY_SORT.index(sort_type) || :import_time
      query[:file_sort_asc] = sort_ascending

      query[:return_file_ids] = return_flag.include?(:ids)
      query[:return_hashes] = return_flag.include?(:hashes)
      query.compact!
      fail ArgumentError, "Return nothing." if query.select do |k, v| k.start_with?('return_') end.all? do |k, v| !v end

      request :GET, '/get_files/search_files',
        context: context,
        query: query
    end
    def query_fetch_metadata(ids: nil, hashes: nil, output_level: :detailed, notes: false, context: nil)
      query = {}

      output_level_value = QUERY_METADATA_DETAIL.index(output_level) || 2
      query[:create_new_file_ids] = false
      query[:only_return_identifiers] = output_level_value <= QUERY_METADATA_DETAIL.index(:why)
      query[:only_return_basic_information] = output_level_value == QUERY_METADATA_DETAIL.index(:basic)
      query[:detailed_url_information] = output_level_value >= QUERY_METADATA_DETAIL.index(:deep)
      query[:hide_service_names_tags] = true
      query[:include_notes] = notes
      query.compact!

      output = []
      [[:file_ids, :file_id, ids], [:hashes, :hash, hashes]].each do |key_multi, key_single, iter|
        next unless Enumerable === iter
        iter.each_slice(256) do |iter_group|
          key = iter_group.size > 1 ? key_multi : key_single
          slice_query = {key => nil}.update(query).update(key => iter_group.size > 1 ? iter_group : iter_group.first)

          output.concat request(:GET, '/get_files/file_metadata',
            context: context,
            query: slice_query
          ).fetch('metadata', [])
        end
      end
      output
    end
    def query_get_file_content(id: nil, hash: nil, context: nil)
      query = {}
      query[:file_id] = id
      query[:hash]    = hash
      query.compact!
      return if query.empty?

      request(:GET, '/get_files/file',
        context: context,
        query: query,
      )
    end
    def query_get_file_thumbnail(id: nil, hash: nil, context: nil)
      query = {}
      query[:file_id] = id
      query[:hash]    = hash
      query.compact!
      return if query.empty?

      request(:GET, '/get_files/thumbnail',
        context: context,
        query: query,
      )
    end

    def query_search_files(tags, file_service_name: nil, file_service_key: nil, tag_service_name: nil, tag_service_key: nil, sort_type: :import_time, sort_ascending: false, return_flag: [:ids], output_level: :detailed, notes: false, context: nil)
      pointers = query_search_files_pointers(
        tags,
        file_service_name: file_service_name, file_service_key: file_service_key,
        tag_service_name: tag_service_name, tag_service_key: tag_service_key,
        sort_type: sort_type, sort_ascending: sort_ascending,
        return_flag: return_flag,
        context: nil,
      )
      query_fetch_metadata(ids: pointers['file_ids'], hashes: pointers['hashes'], output_level: output_level, notes: false)
    end
  end
end