require 'tamashii/common'
module Tamashii
  module Client
    class Config < Tamashii::Config
      register :log_file, STDOUT

      register :use_ssl, false
      register :entry_point, ""
      register :host, "localhost"
      register :port, 3000
      register :opening_timeout, 5
      register :opening_retry_interval, 1
      register :closing_timeout, 5

      def log_level(level = nil)
        return Client.logger.level if level.nil?
        Client.logger.level = level
      end
    end
  end
end
