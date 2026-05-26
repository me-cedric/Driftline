# Dependency Decisions

Driftline keeps dependencies intentionally small, but now includes Apple SwiftNIO SSH as the foundation for the experimental native SSH/SFTP backend.

## Rationale

- Security-sensitive apps benefit from a small dependency graph.
- SwiftPM build/test should stay reasonable after the first dependency resolve.
- SFTP implementation choices need deliberate evaluation.

## SFTP Options

- System `ssh`/`sftp`: stable default, mature tools, careful process management required.
- SwiftNIO SSH: native Swift SSH foundation, supports the future password/private-key auth path without leaking secrets into process arguments, but still requires Driftline to implement the SFTP subsystem on top.
- libssh2 wrapper: mature lower-level library, wrapper and distribution complexity.
- Traversio: native Swift SFTP/password support, but AGPL/commercial licensing does not fit Driftline's MIT repository by default.

Decision: keep the secure system SSH adapter as the production default, pin `swift-nio-ssh` at a Swift 5.10-compatible release for the experimental native backend, and avoid AGPL/commercial SFTP dependencies unless the project license strategy changes.
