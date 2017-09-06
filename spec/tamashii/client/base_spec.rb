require 'spec_helper'

RSpec.describe Tamashii::Client::Base do

  let(:driver) { instance_double(WebSocket::Driver::Client) }
  let(:nio) { instance_double(NIO::Selector) }
  let(:monitor) { instance_double(NIO::Monitor) }
  let(:string_data) { SecureRandom.hex }
  let(:binary_data) { string_data.unpack("C*") }

  let(:io) { instance_double(IO) }

  before do
    allow(WebSocket::Driver).to receive(:client).and_return(driver)
    allow(NIO::Selector).to receive(:new).and_return(nio)

    allow(nio).to receive(:wakeup)

    allow(driver).to receive(:start)
    allow(driver).to receive(:close)
    allow(driver).to receive(:binary)
    allow(driver).to receive(:parse)
    allow(driver).to receive(:on)
  end

  context "mocked thread" do
    before(:each) do
      allow(Thread).to receive(:new) {|&block| @thread_block = block}
      allow(Concurrent::ScheduledTask).to receive(:execute) {|interval, &block| block.call}
      allow(subject).to receive(:loop) {|&block| block.call}
    end


    describe "#open_socket_async" do
      it "create a scheduled task that finally open the socket" do
        expect(Concurrent::ScheduledTask).to receive(:execute) {|interval, &block| block.call}
        expect_any_instance_of(described_class).to receive(:open_socket).and_return(io)
        subject.open_socket_async
      end
    end

    describe "#open_socket_runner" do
      context "when the open_socket is success" do
        before do
          allow(subject).to receive(:post) { |task, &block| (task || block).call }
          allow(subject).to receive(:open_socket).and_return(io)
        end

        let(:callback) { proc { "socket_opened" } }

        it "register the io to nio selector, call the callback with :socket_opened and starts the websocket driver" do
          subject.on(:socket_opened, &callback)
          expect(nio).to receive(:register).with(io, :r).and_return(monitor)
          expect(callback).to receive(:call)
          expect(subject).to receive(:start_websocket_driver)
          subject.open_socket_runner
        end
      end

      context "when the open_socket returns nil" do
        before do
          allow(subject).to receive(:open_socket).and_return(nil)
        end

        it "calls the open_socket_async again" do
          expect(subject).to receive(:open_socket_async)
          subject.open_socket_runner
        end
      end

    end

    describe "#open_socket" do
      let(:tcp_socket) { instance_double(TCPSocket) }
      let(:ssl_socket) { instance_double(OpenSSL::SSL::SSLSocket) }

      context "use ssl" do
        before do
          allow(Tamashii::Client::Config).to receive(:use_ssl).and_return(true)
        end
        it "create the socket by called OpenSSL::SSL::SSLSocket with a TCP socket" do
          expect(TCPSocket).to receive(:new).and_return(tcp_socket)
          expect(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket).and_return(ssl_socket)
          expect(ssl_socket).to receive(:connect).and_return(io)
          expect(subject.open_socket).to be io
        end
      end

      context "does not use ssl" do
        before do
          allow(Tamashii::Client::Config).to receive(:use_ssl).and_return(false)
        end
        it "create the socket by called OpenSSL::SSL::SSLSocket" do
          expect(TCPSocket).to receive(:new).and_return(tcp_socket)
          expect(subject.open_socket).to be tcp_socket
        end
      end

      context "when timeout is reach" do
        before do
          allow(Timeout).to receive(:timeout).and_raise(Timeout::Error) 
        end

        it "returns nil" do
          expect(subject.open_socket).to be nil
        end
      end
      
      context "when other error happens in the block" do
        before do
          allow(Timeout).to receive(:timeout) do
            raise RuntimeError, "Error in the block"
          end
        end

        it "returns nil" do
          expect(subject.open_socket).to be nil
        end
      end
    end


    describe "#flush_write_buffer" do
      context "when write buffer is empty and write head is nil" do
        before do
          subject.instance_variable_set(:@write_buffer, Queue.new)
          subject.instance_variable_set(:@write_head, nil)
        end
        it "returns true" do
          expect(subject.flush_write_buffer).to be true
        end
      end

      shared_examples "call the process_flush" do
        context "when the process_flush returns true" do
          it "leave the loop with return value nil" do
            expect(subject).to receive(:process_flush).and_return(true)
            expect(subject.flush_write_buffer).to eq nil
          end
        end

        context "when the process_flush returns false" do
          it "leave the loop with return value false" do
            expect(subject).to receive(:process_flush).and_return(false)
            expect(subject.flush_write_buffer).to eq false
          end
        end
      end

      context "when write head is nil but the buffer is not empty" do
        let(:new_unit) { SecureRandom.hex }
        before do
          subject.instance_variable_set(:@write_buffer, Queue.new.tap{|q| q << new_unit})
          subject.instance_variable_set(:@write_head, nil)
        end

        it "it pops a unit from write buffer" do
          expect(subject).to receive(:process_flush)
          subject.flush_write_buffer
          expect(subject.instance_variable_get(:@write_head)).to be new_unit
        end

        it_behaves_like "call the process_flush"
      end

      context "when write head is not nil" do
        let(:write_head) { SecureRandom.hex }
        before do
          subject.instance_variable_set(:@write_head, write_head)
        end

        it_behaves_like "call the process_flush"

      end
    end

    describe "#process_flush" do
      def write_head_instance
        subject.instance_variable_get(:@write_head)
      end

      let(:write_head) { SecureRandom.hex }
      before do
        subject.instance_variable_set(:@io, io)
        subject.instance_variable_set(:@write_head, write_head)
      end

      context "when io is not writable" do
        before do
          allow(io).to receive(:write_nonblock).with(write_head, anything).and_return(:wait_writable)
        end

        it "returns false and keep the write_head untouched" do
          expect(subject.process_flush).to eq false
          expect(write_head_instance).to be write_head
        end
      end

      context "when io can only write part of data" do
        let(:written_size) { 1 }
        before do
          allow(io).to receive(:write_nonblock).with(write_head, anything).and_return(written_size)
        end

        it "slice the write_head and return false" do
          expect(subject.process_flush).to eq false
          expect(write_head_instance).to eq write_head[1..-1]
        end
      end

      context "when io can write all data" do
        before do
          allow(io).to receive(:write_nonblock).with(write_head, anything).and_return(write_head.bytesize)
        end
        it "returns true and set write_head to nil" do
          expect(subject.process_flush).to eq true
          expect(write_head_instance).to be nil
        end
      end
    end

    describe "#call_callback" do
      let(:event) { :open }
      let(:callback) { proc { "open_callback" } }

      before do
        subject.on(event, &callback)
      end
      it "call the callback with that event" do
        expect(callback).to receive(:call)
        subject.call_callback(event)
      end
    end

    describe "#close_driver" do
      before do
        allow(subject).to receive(:post) { |&block| block.call }
        subject.instance_variable_set(:@driver, driver)
      end
      it "call the driver#close" do
        expect(driver).to receive(:close)
        subject.close_driver
      end
    end

    describe "#abort_open_socket_task" do
      let(:scheduled_task) { instance_double(Concurrent::ScheduledTask) }
      before do
        subject.instance_variable_set(:@open_socket_task, scheduled_task)
      end
      it "cancel the scheduled task if exists" do
        expect(scheduled_task).to receive(:cancel)
        subject.abort_open_socket_task
      end
    end

    describe "#start_websocket_driver" do
      it "register open, close, message, error callbacks on driver and starts it" do
        expect(driver).to receive(:start)
        [:open, :close, :message, :error].each do |event|
          expect(driver).to receive(:on).with(event, anything)
        end
        subject.start_websocket_driver
      end
    end

    describe "#run" do

      before do
        expect(subject).to receive(:open_socket_async) do
          subject.instance_variable_set(:@driver, driver)
          subject.instance_variable_set(:@io, io)
        end
      end

      context "we do not care the loop body" do
        before do
          allow(subject).to receive(:loop) {}
        end
        it "calls worker_cleanup with true finally" do
          expect(subject).to receive(:worker_cleanup).with(true)
          subject.run
        end
      end

      context "when client is stopped" do
        before do
          allow(subject).to receive(:stopped?).and_return(true)
        end
        it "terminates the loop and call nio#close, does not call select anymore" do
          expect(nio).not_to receive(:select)
          expect(nio).to receive(:close)
          subject.run 
        end
      end

      context "when client is not stopped" do
        let(:todo_block) { proc { "todo block" } }
        before do
          allow(subject).to receive(:stopped?).and_return(false)
          subject.post(&todo_block)
        end

        it "processes the todo and calls nio#select" do
          expect(todo_block).to receive(:call)
          expect(nio).to receive(:select)
          subject.run
        end

        context "when monitors are available" do
          before do
            allow(nio).to receive(:select).and_return([monitor])
            allow(monitor).to receive(:writable?).and_return(false)
            allow(monitor).to receive(:readable?).and_return(false)
          end

          context "when monitor is writable?" do
            before do
              allow(monitor).to receive(:writable?).and_return(true)
            end

            context "when successfully flush the data into network" do
              it "changes the monitor's interests to :r" do
                expect(subject).to receive(:flush_write_buffer).and_return(true)
                expect(monitor).to receive(:interests=).with(:r)
                subject.run
              end
            end
          end

          context "when monitor is readable?" do
            before do
              allow(monitor).to receive(:readable?).and_return(true)
            end
            it "calls read" do
              expect(subject).to receive(:read)
              subject.run
            end
          end

        end
      end
    end

    describe "#read" do
      before do
        subject.instance_variable_set(:@driver, driver)
        subject.instance_variable_set(:@io, io)
        allow(io).to receive(:read_nonblock).and_return(incoming)
      end

      context "when socket is not readable" do
        let(:incoming) { :wait_readable }
        it "returns false" do
          expect(subject.read).to be false
        end
      end

      context "when socket is closed" do
        let(:incoming) { nil }
        it "calls server gone" do
          expect(subject).to receive(:server_gone)
          subject.read
        end
      end

      context "when data is available" do
        let(:incoming) { SecureRandom.hex }

        it "pass it to the driver" do
          expect(driver).to receive(:parse).with(incoming)
          subject.read
        end

        context "when error happens in the driver" do
          before do
            allow(driver).to receive(:parse).and_raise RuntimeError
          end
          
          it "calls server gone" do
          expect(subject).to receive(:server_gone)
          subject.read

          end
        end
      end

    end

    describe "#server_gone" do
      let(:socket_closed_callback) { proc { "socket closed" } }
      
      before do
        subject.instance_variable_set(:@driver, driver)
        subject.instance_variable_set(:@io, io)
        subject.instance_variable_set(:@nio, nio)

        expect(io).to receive(:close)
        expect(nio).to receive(:deregister).with(io)
      end

      it "makes opened? become false" do
        subject.server_gone
        expect(subject.opened?).to be false
      end

      it "call the callback 'socket_closed'" do
        subject.on(:socket_closed, &socket_closed_callback)
        expect(socket_closed_callback).to receive(:call)
        subject.server_gone
      end

      context "when client is closing" do
        before do
          allow(subject).to receive(:closing?).and_return(true)
        end
        it "calls stop" do
          expect(subject).to receive(:stop)
          subject.server_gone
        end
      end

      context "when client is not closing" do
        before do
          allow(subject).to receive(:closing?).and_return(false)
        end
        it "re-create the socket" do
          expect(subject).to receive(:open_socket_async)
          subject.server_gone
        end
      end


    end

    describe "#stop" do
      it "makes the client being stopped" do
        subject.stop
        expect(subject.stopped?).to be true
      end
    end
  end # end of mock thead


  context "the caller thread" do
    let(:worker_thread) { instance_double(Thread) }
    before do
      allow(Thread).to receive(:new).and_return(worker_thread)
      allow(subject).to receive(:post) { |task, &block| (task || block).call }
      subject.instance_variable_set(:@driver, driver)
    end

    describe "#wakeup" do
      it "call the nio#wakeup" do
        expect(nio).to receive(:wakeup) 
        subject.wakeup
      end
    end

    describe "#close" do
      context "when server is opened" do
        before do
          allow(subject).to receive(:opened?).and_return(true)
        end
        it "close the driver instead of stopping" do
          expect(subject).to receive(:close_driver)
          expect(subject).not_to receive(:stop)
          subject.close
        end
      end

      context "when server not opened" do
        before do
          allow(subject).to receive(:opened?).and_return(false)
        end
        it "stops the client and abort the opening task" do
          expect(subject).to receive(:stop)
          expect(subject).to receive(:abort_open_socket_task)
          subject.close
        end
      end
    end

    describe "#transmit" do
      let(:write_buffer) { subject.instance_variable_get(:@write_buffer) }
      context "when server is opened" do
        before do
          allow(subject).to receive(:opened?).and_return(true)
        end
        it "sends the binary data to the driver and returns true" do
          expect(driver).to receive(:binary).with(binary_data)
          expect(subject.transmit(binary_data)).to eq true
        end

        it "convert the string data to binary and then sends the driver, finally returns true" do
          expect(driver).to receive(:binary).with(binary_data)
          expect(subject.transmit(string_data)).to eq true
        end
      end
      context "when server is not opened" do
        before do
          allow(subject).to receive(:opened?).and_return(false)
        end
        it "does not send the binary data to the driver but returns false" do
          expect(driver).not_to receive(:binary)
          expect(subject.transmit(binary_data)).to eq false
        end
      end
    end

    describe "#write" do
      let(:write_buffer) { subject.instance_variable_get(:@write_buffer) }
      it "puts the data to the write buffer and return true" do
        old_size = write_buffer.size
        subject.write(string_data)
        expect(write_buffer.size).to eq (old_size + 1)
      end
    end

    describe "#on" do
      let(:callbacks) { subject.instance_variable_get(:@callbacks) }
      let(:event) { :event }
      let(:callable) { proc { "callable" } }
      let(:block) { proc { "block" } }
      context "when only callable given" do
        it "registers the given callable" do
          subject.on(:event, callable)
          expect(callbacks[event]).to be callable
        end
      end

      context "when only block given" do
        it "registers the given block" do
          subject.on(:event, &block)
          expect(callbacks[event]).to be block
        end
      end

      context "when both callable and block given" do
        it "registers the given callable" do
          subject.on(:event, callable, &block)
          expect(callbacks[event]).to be callable
        end
      end
    end

    describe "#kill_worker_thread" do
      it "force exit the thread and call the worker_cleanup with false" do
        expect(worker_thread).to receive(:exit)
        expect(subject).to receive(:worker_cleanup).with(false)
        subject.kill_worker_thread
      end
    end

    describe "#wait_for_worker_thread" do
      context "when the join is successful" do
        before do
          allow(worker_thread).to receive(:join).and_return(worker_thread)
        end

        it "returns with any call to worker thread" do
          subject.wait_for_worker_thread
        end
      end

      context "when the join is not successful" do
        before do
          allow(worker_thread).to receive(:join).and_return(nil)
        end

        it "kill the worker thread" do
          expect(subject).to receive(:kill_worker_thread)
          subject.wait_for_worker_thread
        end
      end
    end

  end
end
