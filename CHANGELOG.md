# Legion::Transport ChangeLog

## [1.3.5] - 2026-03-22

### Changed
- Boot connection log now includes username and vhost: `amqp://user@host:port/vhost`

## [1.3.4] - 2026-03-22

### Added
- Comprehensive logging across transport operations using `Legion::Logging` (guarded with `defined?`)
- `connection.rb`: `.info` on successful connect (host:port), `.info` on shutdown, `.debug` on per-thread channel creation
- `consumer.rb`: `.info` on subscribe with queue name and consumer tag
- `message.rb`: `.debug` on successful publish (exchange, routing_key, class), `.debug` when encryption is applied
- `messages/task.rb`: `.debug` on routing_key derivation
- `messages/subtask.rb`: `.debug` on routing_key derivation with function_id
- `messages/dynamic.rb`: `.debug` on routing_key/function_id derivation
- `local.rb`: `.info` on setup and shutdown, `.debug` on publish and subscribe
- `helpers/pool.rb`: `.warn` on pool timeout, `.debug` on checkout/checkin with pool state
- `helpers/channel_pool.rb`: `.debug` on channel borrow/return with pool state, `.info` on close_all
- `tenant_provisioner.rb`: `.info` on provision/deprovision success, `.warn` on failure
- `tenant_quota.rb`: `.warn` before raising quota exceeded errors (message rate and byte rate)

## [1.3.3] - 2026-03-22

### Added
- TLS/mTLS direct-settings path in `Connection::SSL#tls_options`: reads `transport.tls`, `transport.tls_ca_cert`, `transport.tls_client_cert`, `transport.tls_client_key`, and `transport.verify_peer` from Legion::Settings when `Legion::Crypt::TLS` is not available
- `verify_peer` defaults to `true` when not explicitly set to `false`
- Logging via `Legion::Logging.info '[Transport] TLS enabled for RabbitMQ connection'` (guarded with `defined?`) when TLS is configured via either path
- 7 new specs covering direct-settings TLS path (358 total, 0 failures)

## [1.3.2] - 2026-03-21

### Added
- `Legion::Transport::Exchanges::Logging`: topic exchange (`legion.logging`) for structured log event publishing
- `Legion::Transport::Queues::RegionOutbound`: durable outbound queues for cross-region message routing (per-peer, skips current region)
- `Legion::Transport::Messages::RegionReRoute`: re-route message type for forwarding tasks to target regions

## [1.3.0] - 2026-03-21

### Added
- RabbitMQ cluster support: `cluster_nodes`, `connection_pool_size`, `region`, `management_port`, `quorum_queue_policy` settings
- Cluster node rotation: `cluster_nodes` merged into `resolved_hosts` with shuffle for load distribution
- Connection pool (`Helpers::Pool`): mutex-protected pool of Bunny sessions with configurable size and timeout
- Channel pool (`Helpers::ChannelPool`): per-connection ring buffer of channels with borrow/return
- Region header injection: `x-legion-region` and `x-legion-region-affinity` headers on published messages when region is configured
- Quorum queue policy helper (`Helpers::Policy`): idempotent HTTP PUT to RabbitMQ Management API, opt-in via `quorum_queue_policy.enabled`
- Connection failover: retry loop across all cluster nodes on TCPConnectionFailed/AuthFailure/ECONNREFUSED
- `Legion::Transport::PoolTimeout` and `Legion::Transport::ClusterUnavailable` error classes

### Changed
- `connection_timeout` default 1 -> 10, `network_recovery_interval` default 1 -> 2
- `build_bunny_opts` now merges `cluster_nodes` into resolved hosts before building Bunny options

## [1.2.9] - 2026-03-21

### Changed
- `Connection::SSL` module refactored to use `Legion::Crypt::TLS.resolve` for TLS configuration
- Removed legacy `use_tls?`, `tls_cert`, `tls_key`, `ca_certs`, `verify_peer?` methods
- TLS options now merged into Bunny connection opts via `tls_options` method
- SSL module auto-required and included in `Connection` class

## [1.2.8] - 2026-03-21

### Added
- `TenantTopology` module: exchange/queue name prefixing with tenant context (`t.<tenant_id>.<name>`); disabled by default; shared exchanges (`legion.control`, `legion.health`, `legion.audit`) are never prefixed; delegates to `Legion::TenantContext.current_tenant_id` when no explicit tenant_id given
- `TenantProvisioner` module: provisions and deprovisions RabbitMQ topology (topic exchanges for tasks/results/events + fanout DLX) for a given tenant; accepts optional channel kwarg for reuse
- `TenantQuota` module: application-level sliding-window rate limiting per tenant; enforces `messages_per_second` and `bytes_per_second` limits from settings; raises `TenantQuota::QuotaExceededError` on violation
- `Settings.tenant_topology` defaults block: `enabled: false`, `prefix_format`, `shared_exchanges`, `auto_provision: true`, `quotas: {}`
- 61 new specs covering all three modules (227 total, 0 failures)

## [1.2.7] - 2026-03-20

### Added
- `legion_protocol_version: '2.0'` header on all published AMQP messages

## [1.2.6] - 2026-03-20

### Changed
- Version bump to trigger CI rebuild

## [1.2.5] - 2026-03-20

### Added
- `Settings.resolve_hosts` — merges `host:`, `hosts:`, `server:`, `servers:` into a unified deduped list with default AMQP port (5672) injected where missing
- `Settings::DEFAULT_AMQP_PORT` constant (5672)
- Multi-host RabbitMQ cluster failover via Bunny's native `hosts:` parameter when 2+ hosts configured
- Support for `server:` and `servers:` keys in transport settings (consistency with legion-cache)

### Fixed
- Port default changed from string `"5672"` to integer `5672` — fixes SSL auto-detect comparison in `Connection::SSL.use_tls?` which compared against integer `5671`
- SSL port auto-detect now uses `.to_i` for robustness

## [1.2.4] - 2026-03-20

### Fixed
- Add `logger` gem as runtime dependency for Ruby 4.0 compatibility (extracted from stdlib)
- Disable DNS bootstrap in test environment to prevent `NameError` from legion-settings 1.3.5

## [1.2.3] - 2026-03-19

### Added
- `Legion::Transport::Spool` JSONL disk buffer for offline message persistence when AMQP is unavailable
- Automatic spool intercept on `Message#publish` Bunny connection errors with configurable limits
- Spool drain reads oldest-first with file rotation and stale eviction (72hr TTL, 10MB/file, 500MB total, 100 files max)

## [1.2.2] - 2026-03-17

### Added
- `Exchanges::Agent` topic exchange for identity-bound agent communication
- `Queues::Agent` per-agent queue (`agent.<agent_id>`) with auto-delete lifecycle
- Agent exchange separates identity-scoped traffic from infrastructure node traffic

## [1.2.1] - 2026-03-16

### Added
- `Legion::Transport::Local` in-memory pub/sub for local development mode (no RabbitMQ required)

### Changed
- Specs for all previously untested messages/, queues/, and exchanges/ subdirectories
- Coverage for 18 source files: 7 messages, 5 queues, 4 exchanges (plus task message)
- Line coverage increased from 65.9% to 81.64%

## v1.2.0
Moving from BitBucket to GitHub. All git history is reset from this point on