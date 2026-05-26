# Architecture Overview

Driftline separates domain, infrastructure, UI, and release concerns.

```mermaid
flowchart LR
  UI["SwiftUI App"] --> Core["DriftlineCore"]
  CLI["driftline CLI"] --> Core
  Core --> Security["CredentialStore + HostTrustStore"]
  Core --> Persistence["Profile + History Repositories"]
  Core --> Local["LocalFileSystemClient"]
  Core --> Remote["RemoteFileSystemClient"]
  Remote --> SFTP["SystemSFTP / Future Native SFTP"]
  Remote --> FTP["FTP Adapter"]
  Remote --> FTPS["FTPS Adapter"]
```

SwiftUI owns app presentation state. `DriftlineCore` owns behavior contracts and testable domain logic.

Performance considerations are tracked in [performance.md](performance.md).
