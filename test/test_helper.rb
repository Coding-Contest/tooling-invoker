ENV["EXERCISM_ENV"] = "test"

gem "minitest"
require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"
require "mocha/minitest"
require "timecop"

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require "tooling_invoker"

module Minitest
  class Test
    def config
      ToolingInvoker.config
    end
  end
end
