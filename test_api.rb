require_relative 'api'

Hydrus::SimpleAPI.new(
  # please put correct one in here!
  '0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff',
  url: hydrus_url,
  session: false,
).tap do |client|

  puts "Supports CBOR? #{client.cbor?}"
  puts "Server Version:"
  p client.get('/api_version')
  puts "Services:"
  p client.get('/get_services')
  puts
  puts "Tags:"
  tags = ['character:sakurai_momoka']
  clean_tags = client.get('/add_tags/clean_tags', query: {tags: tags})
  p tags, clean_tags

rescue Net::HTTPExceptions => e
  $stderr.puts "Received HTTP #{e.data.code}"
  $stderr.puts e.response.body
end

Hydrus::SimpleAPI.new(
  # please put wrong one in here!
  '0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff',
  url: hydrus_url,
  session: true,
).tap do |client|

  p client.get('/verify_access_key')


rescue Net::HTTPExceptions => e
  $stderr.puts "Received HTTP #{e.data.code} (#{e.class}, #{e.response.class})"
  $stderr.puts e.response.body
end
