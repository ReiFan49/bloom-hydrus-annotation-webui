require 'bundler'
require 'json'
Bundler.require :default, :default

require_relative 'server'

use Rack::Reloader, 0
run Hydrus::TaggingServer.new(
  File.expand_path('./config.json', __dir__),
  File.expand_path('./state.bin', __dir__),
)