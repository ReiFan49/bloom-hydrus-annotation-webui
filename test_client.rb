require_relative 'client'

Hydrus::Client.new(
  hydrus_url,
  '0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff',
).tap do |client|
  p client.tag_search('mo')
  p client.query_search_files(['character:sakurai momoka'])
rescue Net::HTTPExceptions => e
  $stderr.puts "Received HTTP #{e.data.code}"
  $stderr.puts e.response.body
end

Hydrus::Client.new(
  hydrus_url,
  nil,
).tap do |client|
  p client.tag_search('momoka')
rescue Net::HTTPExceptions => e
  $stderr.puts "Received HTTP #{e.data.code}"
  $stderr.puts e.response.body
  $stderr.puts e.backtrace
ensure
  p client
end
