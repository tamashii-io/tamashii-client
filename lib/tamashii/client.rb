require "tamashii/common"
require "tamashii/client/config"

module Tamashii
  module Client
    autoload :Base, "tamashii/client/base"

    def self.config(&block)
      return Config.class_eval(&block) if block_given?
      Config
    end

    def self.logger
      @logger ||= Tamashii::Logger.new(Config.log_file).tap do |logger|
        logger.progname = "WebSocket Client"
      end
    end
  end
end
