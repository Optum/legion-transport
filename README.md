Legion::Transport
=====

Legion::Transport is the gem responsible for connecting LegionIO to the FIFO queue system(RabbitMQ over AMQP 0.9.1)

Supported Ruby versions and implementations
------------------------------------------------

Legion::Transport should work identically on:

* JRuby 9.2+
* Ruby 2.4+


Installation and Usage
------------------------

You can verify your installation using this piece of code:

```bash
gem install legion-transport
```

```ruby
require 'legion/transport'
conn = Legion::Transport::Connection
conn.setup
conn.channel # => ::Bunny::Channel
conn.session # => ::Bunny::Session
```

Settings
----------

```json
{
  "type": "rabbitmq",
  "connected": false,
  "logger_level": "info",
  "messages": {
    "encrypt": false,
    "ttl": null,
    "priority": 0,
    "persistent": true
  },
  "prefetch": 2,
  "exchanges": {
    "type": "topic",
    "arguments": {},
    "auto_delete": false,
    "durable": true,
    "internal": false
  },
  "queues": {
    "manual_ack": true,
    "durable": true,
    "exclusive": false,
    "block": false,
    "auto_delete": false,
    "arguments": {
      "x-max-priority": 255,
      "x-overflow": "reject-publish"
    }
  },
  "connection": {
    "read_timeout": 1,
    "heartbeat": 30,
    "automatically_recover": true,
    "continuation_timeout": 4000,
    "network_recovery_interval": 1,
    "connection_timeout": 1,
    "frame_max": 65536,
    "user": "guest",
    "password": "guest",
    "host": "127.0.0.1",
    "port": "5672",
    "vhost": "/",
    "recovery_attempts": 100,
    "logger_level": "info",
    "connected": false
  },
  "channel": {
    "default_worker_pool_size": 1,
    "session_worker_pool_size": 8
  }
}
```
Authors
----------

* [Matthew Iverson](https://github.com/Esity) - current maintainer
