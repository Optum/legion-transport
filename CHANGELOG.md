# Legion::Transport ChangeLog

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