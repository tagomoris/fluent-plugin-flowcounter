require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'fluent/test'
require 'fluent/test/driver/output'
require 'fluent/plugin/out_flowcounter'

class Test::Unit::TestCase
end

def waiting(seconds)
  begin
    Timeout.timeout(seconds) do
      yield
    end
  rescue Timeout::Error
    raise "Timed out with timeout second #{seconds}"
  end
end
