$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require 'tempfile'
require 'securerandom'
require 'simplecov'

SimpleCov.start do
  add_filter "/spec/"
  track_files "lib/**/*.rb"
end

require "tamashii/client"

Tamashii::Client.config do
  log_file = Tempfile.new.path
end
