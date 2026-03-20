# legion-transport: AMQP Transport Layer for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Ruby gem that manages the connection between LegionIO and its FIFO queue system (RabbitMQ over AMQP 0.9.1). Provides abstractions for exchanges, queues, messages, and consumers with thread-safe connection management.

**GitHub**: https://github.com/LegionIO/legion-transport
**Version**: 1.2.3
**License**: Apache-2.0

## Architecture

```
Legion::Transport
├── Connection          # Thread-safe RabbitMQ session/channel management
│   ├── SSL             # TLS configuration (cert, key, CA, Vault PKI)
│   └── Vault           # Vault-based credential retrieval (stub)
├── Exchange            # Base exchange class (extends Bunny::Exchange)
│   └── Exchanges/
│       ├── Task        # Task routing exchange
│       ├── Node        # Node communication exchange (infrastructure: swarms, services, heartbeats)
│       ├── Agent       # Agent communication exchange (identity-bound: GAIA frames, preferences, proactive)
│       ├── Crypt       # Encryption exchange
│       ├── Extensions  # Extension exchange
│       └── Lex         # LEX exchange (inherits Extensions)
├── Queue               # Base queue class (extends Bunny::Queue)
│   └── Queues/
│       ├── Node        # Node queue
│       ├── Agent       # Per-agent queue (auto-delete, routing key: agent.<agent_id>)
│       ├── NodeCrypt   # Node encryption queue
│       ├── NodeStatus  # Node status queue
│       ├── TaskLog     # Task logging queue
│       └── TaskUpdate  # Task update queue
├── Message             # Base message class with publish, encode, encrypt
│   └── Messages/
│       ├── Task        # Task messages with dynamic routing keys
│       ├── SubTask     # Subtask messages (conditions, transforms)
│       ├── Dynamic     # Dynamic function-based messages
│       ├── CheckSubtask
│       ├── LexRegister
│       ├── RequestClusterSecret
│       ├── TaskLog
│       └── TaskUpdate
├── Consumer            # AMQP consumer with auto-generated tags
├── Common              # Shared utilities (channel mgmt, options merging, consumer tags)
├── Local               # In-memory pub/sub for local development mode (no RabbitMQ)
├── Spool               # Disk-backed message buffer: persist messages when RabbitMQ unavailable, replay on reconnect
├── Settings            # Default configuration with env var overrides
└── Version             # 1.2.3
```

## Key Design Patterns

### AMQP Client
Uses `bunny` gem for AMQP 0.9.1. The entry point sets `Legion::Transport::TYPE = 'bunny'` and `Legion::Transport::CONNECTOR = ::Bunny` as constants.

### Thread-Safe Connection Management
- `Concurrent::AtomicReference` wraps the AMQP session (one per process)
- `Concurrent::ThreadLocalVar` provides per-thread channels
- Auto-recovery on blocked/unblocked/recovery events

### Options Merging
`Common#options_builder` deep-merges default options -> class options -> instance options. Used by both Exchange and Queue constructors.

### Auto-Recreate on Mismatch
Both Exchange and Queue classes catch `PreconditionFailed` errors (parameter mismatch with existing RabbitMQ declarations) and attempt to delete + recreate once before raising.

## Dependencies

| Gem | Purpose |
|-----|---------|
| `bunny` (>= 2.23) | CRuby AMQP client |
| `concurrent-ruby` (>= 1.2) | Thread-safe data structures |
| `legion-json` | JSON serialization |
| `legion-settings` | Configuration management |

Optional runtime dependencies:
- `legion-crypt` - Message encryption support
- `legion-data` - Database models (used by Dynamic/SubTask messages)
- `legion-logging` - Structured logging

## Configuration

Settings are loaded via `Legion::Transport::Settings` with env var overrides:

| Env Var | Default | Description |
|---------|---------|-------------|
| `transport.connection.host` | `127.0.0.1` | RabbitMQ host |
| `transport.connection.port` | `5672` | RabbitMQ port |
| `transport.connection.user` | `guest` | RabbitMQ user |
| `transport.connection.password` | `guest` | RabbitMQ password |
| `transport.connection.vhost` | `/` | RabbitMQ vhost |
| `transport.prefetch` | `2` | Consumer prefetch count |
| `transport.messages.encrypt` | `false` | Enable message encryption |
| `transport.messages.ttl` | `nil` | Message TTL |
| `transport.messages.persistent` | `true` | Persistent messages |

Vault integration: If `Legion::Settings[:crypt][:vault][:connected]` is true, credentials are fetched from `rabbitmq/creds/legion` in Vault.

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion/transport.rb` | Entry point, connector detection, logger/settings |
| `lib/legion/transport/connection.rb` | Session/channel lifecycle (setup, reconnect, shutdown) |
| `lib/legion/transport/connection/ssl.rb` | TLS settings module |
| `lib/legion/transport/connection/vault.rb` | Vault PKI integration (stub) |
| `lib/legion/transport/common.rb` | Shared module (channel access, deep_merge, consumer tags) |
| `lib/legion/transport/exchange.rb` | Base Exchange class |
| `lib/legion/transport/exchanges/agent.rb` | Agent exchange for identity-bound communication |
| `lib/legion/transport/queue.rb` | Base Queue class |
| `lib/legion/transport/queues/agent.rb` | Per-agent queue (auto-delete, keyed by agent_id) |
| `lib/legion/transport/message.rb` | Base Message class with publish/encode/encrypt |
| `lib/legion/transport/consumer.rb` | AMQP consumer wrapper |
| `lib/legion/transport/spool.rb` | Disk-backed message buffer (~/.legionio/spool, 10MB/file, 500MB total, 3-day TTL) |
| `lib/legion/transport/settings.rb` | Default config, env var loading, Vault cred fetch |
| `lib/legion/transport/version.rb` | Version constant |
| `spec/` | RSpec test suite |

## Node vs Agent Exchange

Two identity-scoped exchanges separate infrastructure traffic from agent-bound traffic:

| Exchange | Routing Key Pattern | Use Case |
|----------|-------------------|----------|
| `node` | `node.<fqdn/nodename>` | Infrastructure: swarm coordination, service heartbeats, non-identity traffic |
| `agent` | `agent.<agent_id>` | Identity-bound: GAIA cognitive frames, preference queries, proactive messages |

**Agent queue defaults** differ from standard queues:
- `durable: false` — agent queues are ephemeral (recreated on connect)
- `auto_delete: true` — cleaned up when the agent disconnects
- Dead letter exchange: `agent.dlx`
- Agent ID defaults to `Legion::Settings['client']['name']` if not provided

The `agent` exchange is used by `legion-gaia` for inbound cognitive frames (replacing the former `gaia` exchange routing) and by `lex-mesh` for async preference queries via `reply_to` + `correlation_id` RPC.

## Queue Defaults

All queues are created with:
- `durable: true` - survives broker restart
- `manual_ack: true` - explicit acknowledgment required
- `x-max-priority: 255` - priority queue support
- `x-overflow: reject-publish` - rejects new messages when full
- Dead letter exchange: `<exchange>.dlx`

## Exchange Defaults

All exchanges are created as:
- `type: topic` - supports routing key pattern matching
- `durable: true` - survives broker restart
- `auto_delete: false` - persists when no queues bound

## Testing

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

Spec count: 166 examples

---

**Maintained By**: Matthew Iverson (@Esity)
