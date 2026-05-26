# Performance

Driftline should stay lightweight even when folders and queues become large.

## Current Measures

- Directory listing and transfers use async APIs so the SwiftUI main thread remains responsive.
- Local file listing uses `FileManager` resource keys instead of repeatedly asking the filesystem for individual attributes.
- Sorting and hidden-file filtering live in testable core helpers.
- Transfer progress is streamed from the process output and published as job updates instead of waiting for command completion.
- Remote operations are isolated behind protocol adapters so native SFTP libraries, resumable transfers, or paginated listings can replace system tools later.

## Constraints

- Very large local folders are currently loaded as a single array. A virtualized or paginated model should be introduced before claiming enterprise-scale directory performance.
- Remote SFTP listing currently shells through `ssh find`; it is practical for an MVP, but a native SSH/SFTP backend will give better cancellation, structured errors, and incremental listing.
- Transfer history is JSON-backed and should be capped or migrated to SQLite/SwiftData before storing long-lived high-volume history.

## Future Work

- Incremental remote listing and cancellation-aware directory refresh.
- Transfer progress throttling for very high-frequency process output.
- Bounded transfer history retention with compaction.
- Configurable transfer concurrency and bandwidth limits.
- Large-folder UI performance pass using Instruments.
- Memory-conscious streaming checksums for optional verification.
