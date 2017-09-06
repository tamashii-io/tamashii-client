require 'tamashii/common'
module Tamashii
  module Client
    class Config < Tamashii::Config
      register :log_file, STDOUT
      register :use_ssl, false
      register :entry_point, "/tamashii"
      register :host, "localhost"
      register :port, 3000
      register :opening_timeout, 5
      register :closing_timeout, 5
    end
  end
end
