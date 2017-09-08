Tamashii Client [![Gem Version](https://badge.fury.io/rb/tamashii-client.svg)](https://badge.fury.io/rb/tamashii-client)
===

Tamashii Client is the websocket client for the  [Tamashii](https://github.com/tamashii-io/tamashii) project. It is event-driven and it provides high-level API for users to communicates with WebSocket server easily.

## Installation

Add the following code to your `Gemfile`:

```ruby
gem 'tamashii-client'
```

And then execute:
```ruby
$ bundle install
```

Or install it yourself with:
```ruby
$ gem install tamashii-client
```

## Usage

With Tamashii Client, we just need to focus on how to handle the events such as `on_connect` for connection opened or `on_message` for receiving messages from server.

### Simple Example

A simple example of using Tamashii Client follows. Here we will connect to the [wss://echo.websocket.org](wss://echo.websocket.org), the echo testing for WebSocket.

```ruby
require 'tamashii/client'

# configuration for client. Can be seperated into other file
Tamashii::Client.config do
  # whether to use TLS or not. Here we connect to 'wss', so the value is true
  use_ssl true
  # the hostname WITHOUT url scheme
  host "echo.websocket.org"
  # the port to connect with. 443 for HTTPS and WSS
  # Note the current version client does not infer the port from 'use_ssl'
  # So you must explictly specifiy the port to use
  port 443
  # the log file for internel connection log
  # default is STDOUT
  log_file 'tamashii.log'
end

client = Tamashii::Client::Base.new
@server_opened = false

# callback for server opened
# called when the WebSocket connection is readt
client.on(:open) do
  @server_opened = true
end

# callback for receving messages
# The data received is represented in a byte array
# You may need to 'pack' it back to Ruby string
client.on(:message) do |message|
  puts "Received: #{message.pack('C*')}"
end


# sending loop
# We send a request to server every second and terminates after 10 seconds
# In the begining, the server is not opened so the sending may fail.
count = 0
loop do
  sleep 1
  if @server_opened # can also use 'client.opened?'
    client.transmit "Hello World! #{count}"
  else
    puts "Unable to send #{count}: server not opened"
  end
  count += 1
  if count >= 10
    client.close
    break
  end
end
```

The [wss://echo.websocket.org](wss://echo.websocket.org) will echo the messages back to the client. So if everything works fine, you will see following output:

```text
Unable to send 0: server not opened
Received: Hello World! 1
Received: Hello World! 2
Received: Hello World! 3
Received: Hello World! 4
Received: Hello World! 5
Received: Hello World! 6
Received: Hello World! 7
Received: Hello World! 8
Received: Hello World! 9
```

If you look into the log file (`tamashii.log` in this example), you can find the connection details of Tamashii Client.

```log
[2017-09-08 03:39:38] INFO -- WebSocket Client  : Worker Create!
[2017-09-08 03:39:39] INFO -- WebSocket Client  : Trying to open the socket...
[2017-09-08 03:39:40] INFO -- WebSocket Client  : Socket opened!
[2017-09-08 03:39:40] INFO -- WebSocket Client  : WebSocket Server opened
[2017-09-08 03:39:41] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 49]
[2017-09-08 03:39:41] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 50]
[2017-09-08 03:39:42] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 51]
[2017-09-08 03:39:43] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 52]
[2017-09-08 03:39:44] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 53]
[2017-09-08 03:39:45] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 54]
[2017-09-08 03:39:46] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 55]
[2017-09-08 03:39:47] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 56]
[2017-09-08 03:39:48] DEBUG -- WebSocket Client : Message from server: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33, 32, 57]
[2017-09-08 03:39:49] INFO -- WebSocket Client  : WebSocket Server closed
[2017-09-08 03:39:49] INFO -- WebSocket Client  : Socket closed
[2017-09-08 03:39:49] DEBUG -- WebSocket Client : Worker terminales normally
```

The log level can be changed in the configuration using `log_level`. For example, to change to level to `INFO`:
```ruby
Tamashii::Client.config do
  log_level :INFO
end
```

### The events and callbacks

These are events in the Tamashii Client. You can use `on` method to register callbacks for them.
- `socket_opened`
    - When the low-level io socket (`TCPSocket` or `OpenSSL::SSL::SSLSocket`) successfully connected to the server.
    - Receving this event does not imply the server supports WebSocket. Client still cannot send messages at this moment
- `open`
    - When the WebSocket handshake is finished and the connection is opened
    - Client can start sending messages to server after receiving this event.
    - Fired after `socket_opened`
- `message`
    - When the client receives the WebSocket payload from server.
    - The message payload will be pass as the argument of the callback.
- `error`
    - When there is a protocol error due to bad data sent by the other peer.
    - This event is purely informational, you do not need to implement error recovery.
    - The error object will be pass as the argument of the callback.
- `close`
    - When the WebSocket is closed **normally**.
    - Will **NOT** be fired when the connection is closed by low-level IO error such as connection reset.
    - Fired before `socket_closed`
- `socket_closed`
    - When the low-level socket is closed.
    - Will be fired no matter the WebSocket is closed normally or not.



### Cooperate with Tamashii Server

Above example using the [wss://echo.websocket.org](wss://echo.websocket.org) to test your client. You can also use the [Tamashii](https://github.com/tamashii-io/tamashii) server to test your client. Only thing to do is to change the `host` and `port` in the configuration into the one used by your Tamashii server.

## Development

To get the source code

    $ git clone git@github.com:tamashii-io/tamashii-client.git

Initialize the development environment

    $ ./bin/setup

Run the spec

    $ rspec

Installation the version of development on localhost

    $ bundle exec rake install

## Contribution

Please report to us on [Github](https://github.com/tamashii-io/tamashii-client) if there is any bug or suggested modified.

The project was developed by [5xruby Inc.](https://5xruby.tw/)


