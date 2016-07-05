require "simplecov"
require "coveralls"
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start { add_filter "/spec/" }

ENV["MODE"]="test"
# require 'sucker_punch/testing/inline'
require "lita-standup"
require "lita/rspec"
require "pry-byebug"
require 'fakeredis/rspec'
require 'timecop'
require 'dotenv'
Dotenv.load

include Mail::Matchers
# A compatibility mode is provided for older plugins upgrading from Lita 3. Since this plugin
# was generated with Lita 4, the compatibility mode should be left disabled.
Lita.version_3_compatibility_mode = false
