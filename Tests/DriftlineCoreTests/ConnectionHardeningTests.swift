@testable import DriftlineCore
import NIOCore
import NIOEmbedded
import NIOSSH
import XCTest

final class ConnectionHardeningTests: XCTestCase {
    func testServerSentNamesCannotEscapeTheDownloadFolder() {
        let listing = """
        -rw-r--r--    1 ftp      ftp             1 Oct 20 09:15 ../../escape.txt
        -rw-r--r--    1 ftp      ftp             1 Oct 20 09:15 a/b.txt
        -rw-r--r--    1 ftp      ftp             1 Oct 20 09:15 safe.txt
        """

        XCTAssertEqual(FTPListParser.parse(listing, directory: "/", preferences: FileListPreferences()).map(\.name), ["safe.txt"])
        XCTAssertEqual(SFTPLongListingParser.parse(listing, directory: "/", preferences: FileListPreferences()).map(\.name), ["safe.txt"])
    }

    func testUsernamesThatLookLikeOptionsAreRejected() throws {
        let profile = ServerProfile(displayName: "Bad", host: "example.com", protocolKind: .sftp, username: "-oProxyCommand=x", authenticationMethod: .agent)

        XCTAssertThrowsError(try ServerProfileValidator.validate(profile))
        XCTAssertThrowsError(try SSHCommandBuilder.baseArguments(for: profile, knownHostsURL: nil))
        XCTAssertTrue(ServerProfileValidator.isUsableUsername("user@corp.example"))
    }

    func testFolderTransfersTargetTheParentToAvoidNesting() throws {
        XCTAssertEqual(
            try SFTPBatchCommandBuilder.transferCommand(direction: .upload, sourcePath: "/tmp/site", destinationPath: "/var/www/site", isFolder: true),
            "put -r \"/tmp/site\" \"/var/www\"\n"
        )
        XCTAssertEqual(
            try SFTPBatchCommandBuilder.transferCommand(direction: .download, sourcePath: "~/site", destinationPath: "/tmp/site", isFolder: true),
            "get -r \"site\" \"/tmp\"\n"
        )
    }

    func testRsyncFallbackNeedsAMissingRsyncMessage() {
        XCTAssertFalse(RsyncCommandBuilder.remoteRsyncIsMissing(ProcessResult(exitCode: 12, standardOutput: "", standardError: "rsync: connection unexpectedly closed")))
        XCTAssertTrue(RsyncCommandBuilder.remoteRsyncIsMissing(ProcessResult(exitCode: 12, standardOutput: "", standardError: "bash: rsync: command not found")))
        XCTAssertTrue(RsyncCommandBuilder.remoteRsyncIsMissing(ProcessResult(exitCode: 1, standardOutput: "", standardError: "This service allows sftp connections only.")))
    }

    func testCancelReachesOnlyTheClientOfTheJob() async throws {
        let sftp = CountingTransferClient()
        let ftp = CountingTransferClient()
        let routing = ProtocolRoutingTransferClient(sftp: sftp, ftp: ftp)
        let job = TransferJob(direction: .upload, sourcePath: "/tmp/a", destinationPath: "~/a")
        let profile = ServerProfile(displayName: "FTP", host: "h", protocolKind: .ftp, username: "u", authenticationMethod: .none)

        try await routing.enqueue(job, profile: profile, onUpdate: nil)
        try await routing.cancel(id: job.id)

        let sftpCancels = await sftp.cancels
        let ftpCancels = await ftp.cancels
        XCTAssertEqual(sftpCancels, 0)
        XCTAssertEqual(ftpCancels, 1)
    }

    func testNativeAuthFailsInsteadOfWaitingWhenNoMethodFits() throws {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: NIOSSHUserAuthenticationOffer?.self)
        let delegate = NativeSFTPAuthFactory.passwordDelegate(username: "u", password: "p")

        delegate.nextAuthenticationType(availableMethods: .publicKey, nextChallengePromise: promise)

        XCTAssertThrowsError(try promise.futureResult.wait())
    }
}

private actor CountingTransferClient: TransferClient {
    private(set) var cancels = 0

    func enqueue(_: TransferJob, profile _: ServerProfile, onUpdate _: (@Sendable (TransferJob) async -> Void)?) async throws {}

    func cancel(id _: TransferJobID) async throws {
        self.cancels += 1
    }

    func retry(id _: TransferJobID) async throws {}

    func jobs() async -> [TransferJob] {
        []
    }
}
