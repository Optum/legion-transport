# legion-transport Agent Notes

## Scope

`legion-transport` owns AMQP transport primitives (connection, exchanges, queues, messages, consumers), lite-mode local transport, spool/replay, and tenant transport controls.

## Fast Start

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Primary Entry Points

- `lib/legion/transport.rb`
- `lib/legion/transport/connection.rb`
- `lib/legion/transport/exchange.rb`
- `lib/legion/transport/queue.rb`
- `lib/legion/transport/message.rb`
- `lib/legion/transport/in_process.rb`

## Guardrails

- Keep `LEGION_MODE=lite` behavior working; lite mode must avoid Bunny dependencies at runtime.
- Preserve thread-safety patterns (`AtomicReference` session + thread-local channels).
- Queue and exchange defaults are intentional (`topic`, durable defaults, DLX wiring); avoid silent behavior changes.
- `force_reconnect` is socket-first on purpose for stuck sessions; do not simplify this path.
- For optional integrations (`legion-crypt`, `legion-data`, logging), use `defined?` guards.
- Tenant modules (`tenant_provisioner`, `tenant_quota`, `tenant_topology`) must remain idempotent and safe under concurrent publish.

## Validation

- Run targeted specs for changed transport primitives.
- Before handoff, run full `bundle exec rspec` and `bundle exec rubocop`.
