require 'concurrent'
require 'nio'
require 'openssl'
require 'socket'
require 'timeout'
require 'websocket/driver'


require "tamashii/common"
require "tamashii/client/config"


Thread.abort_on_exception = true

module Tamashii
  module Client
    class Base

      attr_reader :url

      def logger
        Client.logger
      end

      def initialize
        @url = "#{Config.use_ssl ? "wss" : "ws"}://#{Config.host}:#{Config.port}/#{Config.entry_point}"

        @callbacks = {}

        @write_head = nil
        @write_buffer = Queue.new

        @nio = NIO::Selector.new
        @todo = Queue.new
        @stopping = false
        @closing = false
        @opened = false
        @thread = Thread.new {run}
      end

      def close
        @closing = true
        if opened?
          @driver.close
        else
          logger.info "Closing: server is not connected, close immediately"
          abort_open_socket_task
          stop
        end
        wait_for_worker_thread
      end

      def abort_open_socket_task
        @open_socket_task&.cancel
      end

      def closing?
        @closing
      end

      def opened?
        @opened
      end

      def stopped?
        @stopping
      end

      # called from user
      def transmit(data)
        if opened?
          data.unpack("C*") if data.is_a?(String)
          @driver.binary(data)
          true
        else
          logger.error "Server not opened. Cannot transmit data!"
          false
        end
      end

      # called from ws driver
      def write(data)
        @write_buffer << data
        @todo << lambda do
          begin
            @monitor&.interests = :rw
          rescue EOFError => e
            # Monitor is closed
            logger.error "Error when writing: #{e.message}"
          end
        end
        wakeup
      end

      def on(event, callable = nil, &block)
        logger.warn "Multiple callbacks detected, ignore the block" if callable && block
        if callable
	  @callbacks[event] = callable
        else
	  @callbacks[event] = block
        end
      end

      private

      def wait_for_worker_thread
        if !@thread.join(Config.closing_timeout)
          logger.error "Unable to stop worker thread in #{Config.closing_timeout} second! Force kill the worker thread"
          @thread.exit
        end
      end

      def wakeup
        @nio.wakeup
      end

      def open_socket
        Timeout::timeout(Config.opening_timeout) do
          if Config.use_ssl
            OpenSSL::SSL::SSLSocket.new(TCPSocket.new(Config.host, Config.port)).connect
          else
            TCPSocket.new(Config.host, Config.port)
          end
        end
      rescue Timeout::Error => e
        logger.error "Opening timeout after #{Config.opening_timeout} seconds"
        nil
      rescue => e
        nil
      end

      def open_socket_runner
        logger.info "Trying to open the socket..."
        if @io = open_socket
          logger.info "Socket opened!"
          call_callback(:socket_opened)
          @todo << lambda do 
            @monitor = @nio.register(@io, :r)
            @opened = true
            start_websocket_driver
          end
          wakeup
        else
          logger.error "Cannot open socket, retry later"
          open_socket_async
        end
      end

      def open_socket_async
        @open_socket_task = Concurrent::ScheduledTask.execute(1, &method(:open_socket_runner))
      end

      def flush_write_buffer
        loop do
          return true if @write_buffer.empty? && @write_head.nil?
          @write_head = @write_buffer.pop if @write_head.nil?
          return false unless process_flush
        end
      end

      def process_flush
        written = @io.write_nonblock(@write_head, exception: false)
        case written
        when @write_head.bytesize
          @write_head = nil
          return true
        when :wait_writable then return false
        else
          @write_head = @write_head.byteslice(written, @write_head.bytesize)
          return false
        end
      end

      def call_callback(event, *args, &block)
        @callbacks[event]&.call(*args, &block)
      end

      def start_websocket_driver
        @driver = WebSocket::Driver.client(self)
        @driver.on :open, proc { |e|
          @opened = true
          logger.info "WebSocket Server opened"
          call_callback(:open)
        }
        @driver.on :close, proc { |e|
          logger.info "WebSocket Server closed"
          call_callback(:close)
          server_gone
        }
        @driver.on :message, proc { |e|
          logger.debug("Message from server: #{e.data}")
          call_callback(:message, e.data)
        }
        @driver.on :error, proc { |e|
          logger.error("WebSocket error: #{e.message}")
          call_callback(:error, e)
        }
        @driver.start
      end

      def run
        open_socket_async
        loop do
          if stopped?
            @nio.close
            break
          end

          @todo.pop(true).call until @todo.empty?

          monitors = @nio.select
          next unless monitors
          monitors.each do |monitor|
            if monitor.writable?
              monitor.interests = :r if flush_write_buffer
            end
            if monitor.readable?
              read
            end
         end
        end
      end

      def read
        incoming = @io.read_nonblock(4096, exception: false)
        case incoming
        when :wait_readable then false
        when nil then server_gone
        else
          @driver.parse(incoming)
        end
      rescue
        server_gone
      end

      def server_gone
        logger.info "Socket closed"
        @opened = false
        @io.close
        @nio.deregister @io
        call_callback(:socket_closed)
        if closing?
          # client should stop the thread
          stop
        else
          # closing is not issued by client, re-open
          open_socket_async
        end
      end


      # this is hard stop, will not issue a websocket close message!
      def stop
        @stopping = true
        wakeup
      end
    end
  end
end