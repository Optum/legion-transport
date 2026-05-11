Always run a full `bundle exec rspec` and `bundle exec rubocop -A` and fix all errors before committing.

# legion-transport: AMQP Transport Layer for LegionIO

RabbitMQ over AMQP 0.9.1. Thread-safe connection management, exchanges, queues, messages, consumers.

## Architecture

```
Legion::Transport
├── Connection          # Thread-safe session/channel, SSL, Vault creds
├── InProcess           # Lite mode adapter
├── Exchange            # Topic exchanges: Task, Node, Agent, Crypt, Extensions, Lex, Logging
├── Queue              # Node, Agent, NodeCrypt, NodeStatus, TaskLog, TaskUpdate, RegionOutbound
├── Message            # Publish, encode, encrypt; Task, SubTask, Dynamic, LexRegister, etc.
├── Consumer           # Auto-generated consumer tags
├── Common             # Channel mgmt, options merging
├── Helper             # Injectable transport mixin for LEX extensions
├── Local              # In-memory pub/sub for lite mode
├── Spool              # Disk-backed buffer, replay on reconnect
├── TenantProvisioner  # Per-tenant exchanges/queues on first publish
├── TenantQuota        # Per-tenant rate limiting
└── TenantTopology     # Topology tracking
```

## Key Design Patterns

**Force Reconnect** — `Connection.force_reconnect` performs socket-first teardown (closes TCP socket before `Bunny::Session#close`) to break stuck connections. Tracks recovery rate over a 5-window/60s sliding window. Calls registered `on_force_reconnect` callbacks. Sets shutdown flag to prevent reconnection loops.

**Lite Mode** — `LEGION_MODE=lite` sets `TYPE='local'`, `CONNECTOR=InProcess`. `Connection.setup` returns an InProcess session, skipping Bunny entirely.

**Thread-Safe Connections** — `Concurrent::AtomicReference` wraps the AMQP session (one per process). `Concurrent::ThreadLocalVar` provides per-thread channels. Auto-recovery on blocked/unblocked/recovery events.

**Auto-Recreate on Mismatch** — Exchange and Queue classes catch `PreconditionFailed` (parameter mismatch with existing declarations) and delete + recreate once before raising.

**Options Merging** — `Common#options_builder` deep-merges default -> class -> instance options for Exchange and Queue constructors.

## Configuration

| Setting | Default | Description |
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

Vault integration: credentials via `lease://rabbitmq#username` URI refs; lease path configured in `crypt.vault.leases.rabbitmq.path`.

## Node vs Agent Exchange

| Exchange | Routing Key | Use Case |
|----------|-------------|----------|
| `node` | `node.<fqdn>` | Infrastructure: swarm coordination, heartbeats |
| `agent` | `agent.<agent_id>` | Identity-bound: GAIA frames, preferences, proactive messages |

Agent queue differences: `durable:false`, `auto_delete:true`, DLX: `agent.dlx`. Agent ID defaults to `Legion::Settings['client']['name']`.

## Queue Defaults

- `durable: true`, `manual_ack: true`
- `x-max-priority: 255`, `x-overflow: reject-publish`
- Dead letter exchange: `<exchange>.dlx`

## Exchange Defaults

- `type: topic`, `durable: true`, `auto_delete: false`

## Testing

448+ specs. Run `bundle exec rspec` and `bundle exec rubocop`.
