require "tamashii/config"
require "tamashii/common"
require "tamashii/client/version"
require "tamashii/client/config"

module Tamashii
  module Client
    autoload :Base, "tamashii/client/base"

    def self.config(&block)
      @config ||= Config.new
      return instance_exec(@config, &block) if block_given?
      @config
    end

    def self.logger
      @logger ||= Tamashii::Logger.new(self.config.log_file).tap do |logger|
        logger.progname = "WebSocket Client"
      end
    end
  end
end
