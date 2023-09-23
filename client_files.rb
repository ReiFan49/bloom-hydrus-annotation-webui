module Hydrus
  module ClientFiles
    def file_import_from(url, context: nil)
      request :POST, '/add_files/add_file',
        context: context,
        body: {
          path: url
        }
    end
    def file_upload_from(file, context: nil)
      request :POST, '/add_files/add_file',
        context: context,
        file: file
    end

    def file_mark_delete(ids: nil, hashes: nil, service_name: nil, service_key: nil, reason: nil, context: nil)
      validate_service 'local_files', name: service_name, key: service_key
      query = {}
      query[:hashes] = hashes.to_a if Enumerable === hashes
      query[:file_ids] = ids.to_a  if Enumerable === ids
      query[:file_service_name] = service_name
      query[:file_service_key] = service_key
      query[:reason] = reason
      query.compact!

      request :POST, '/add_files/delete_files',
        context: context,
        body: query
    end
    def file_mark_undelete(ids: nil, hashes: nil, service_name: nil, service_key: nil, context: nil)
      validate_service 'local_files', name: service_name, key: service_key
      query = {}
      query[:hashes] = hashes.to_a if Enumerable === hashes
      query[:file_ids] = ids.to_a  if Enumerable === ids
      query[:file_service_name] = service_name
      query[:file_service_key] = service_key
      query.compact!

      request :POST, '/add_files/undelete_files',
        context: context,
        body: query
    end
    def file_mark_archive(ids: nil, hashes: nil, context: nil)
      query = {}
      query[:hashes] = hashes.to_a if Enumerable === hashes
      query[:file_ids] = ids.to_a  if Enumerable === ids
      query.compact!

      request :POST, '/add_files/archive_files',
        context: context,
        body: query
    end
    def file_mark_unarchive(ids: nil, hashes: nil, context: nil)
      query = {}
      query[:hashes] = hashes.to_a if Enumerable === hashes
      query[:file_ids] = ids.to_a  if Enumerable === ids
      query.compact!

      request :POST, '/add_files/unarchive_files',
        context: context,
        body: query
    end
  end
end