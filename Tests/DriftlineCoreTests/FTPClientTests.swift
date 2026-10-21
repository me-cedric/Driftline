@testable import DriftlineApp
@testable import DriftlineCore
import XCTest

final class FTPClientTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!

    func testListParserReadsUnixListing() {
        let output = """
        drwxr-xr-x    2 ftp      ftp          4096 Oct 20 09:15 public html
        -rw-r--r--    1 ftp      ftp           123 Jan  1  2024 readme.txt
        lrwxrwxrwx    1 ftp      ftp             9 Oct 01 10:00 latest -> releases/9
        -rw-r--r--    1 1001     100            42 Oct 19 08:00 .hidden
        drwxr-xr-x    1 owner             0 Mar 14  2025 no-group
        """

        let items = FTPListParser.parse(output, directory: "/pub", preferences: FileListPreferences(), now: self.now)

        XCTAssertEqual(items.map(\.name), ["no-group", "public html", "latest", "readme.txt"])
        XCTAssertEqual(items.first { $0.name == "public html" }?.path, "/pub/public html")
        XCTAssertEqual(items.first { $0.name == "latest" }?.kind, .symbolicLink)
        XCTAssertEqual(items.first { $0.name == "readme.txt" }?.size, 123)
        XCTAssertEqual(items.first { $0.name == "no-group" }?.owner, "owner")
        XCTAssertNil(items.first { $0.name == "no-group" }?.group)
    }

    func testListParserReadsWindowsListing() {
        let output = "10-02-24  03:15PM       <DIR>          Reports 2024\r\n01-15-25  09:05AM                 2048 data file.csv\r\n"

        let items = FTPListParser.parse(output, directory: "~", preferences: FileListPreferences(), now: self.now)

        XCTAssertEqual(items.map(\.name), ["Reports 2024", "data file.csv"])
        XCTAssertEqual(items.first?.kind, .folder)
        XCTAssertEqual(items.last?.size, 2048)
        XCTAssertEqual(items.last?.path, "~/data file.csv")
        XCTAssertEqual(Calendar.current.component(.hour, from: items.first?.modifiedAt ?? .distantPast), 15)
    }

    func testCommandPathsAreRelativeToLoginFolderUnlessAbsolute() throws {
        XCTAssertEqual(try FTPCommandBuilder.commandPath("~"), ".")
        XCTAssertEqual(try FTPCommandBuilder.commandPath("~/a b/c"), "a b/c")
        XCTAssertEqual(try FTPCommandBuilder.commandPath("/var/www"), "/var/www")
        XCTAssertThrowsError(try FTPCommandBuilder.commandPath("x\r\nDELE y"))
    }

    func testSecurityModeFollowsPort() {
        var profile = ServerProfile(displayName: "FTPS", host: "h", protocolKind: .ftps, username: "u", authenticationMethod: .none)
        XCTAssertEqual(FTPSecurityMode(profile: profile), .implicitTLS)
        profile.port = 21
        XCTAssertEqual(FTPSecurityMode(profile: profile), .explicitTLS)
        profile.implicitTLS = true
        XCTAssertEqual(FTPSecurityMode(profile: profile), .implicitTLS)
        profile.port = 990
        profile.implicitTLS = false
        XCTAssertEqual(FTPSecurityMode(profile: profile), .explicitTLS)
        profile.protocolKind = .ftp
        XCTAssertEqual(FTPSecurityMode(profile: profile), .none)
    }

    func testEditorKeepsPortAndTLSModeInStep() {
        var draft = ServerProfileDraft()
        draft.changeProtocol(to: .ftps)
        XCTAssertEqual(draft.port, 990)
        XCTAssertTrue(draft.ftpsImplicitTLS)

        draft.changeFTPSMode(implicitTLS: false)
        XCTAssertEqual(draft.port, 21)
        draft.port = 2121
        draft.changeFTPSMode(implicitTLS: true)
        XCTAssertEqual(draft.port, 2121)
        XCTAssertEqual(draft.makeProfile().implicitTLS, true)

        draft.host = "ftpes://files.example.com"
        draft.applyAddressFromHost()
        XCTAssertEqual(draft.port, 21)
        XCTAssertFalse(draft.ftpsImplicitTLS)
    }

    func testProfileWithoutTLSChoiceStillDecodes() throws {
        let profile = ServerProfile(displayName: "Old", host: "h", protocolKind: .ftps, username: "u", authenticationMethod: .none)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any] ?? [:]
        json["implicitTLS"] = nil

        let decoded = try JSONDecoder().decode(ServerProfile.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(decoded.implicitTLS)
        XCTAssertEqual(FTPSecurityMode(profile: decoded), .implicitTLS)
    }

    func testPassiveRepliesGivePort() {
        XCTAssertEqual(FTPCommandBuilder.passivePort(from: FTPReply(code: 227, text: "Entering Passive Mode (10,0,0,5,117,48).")), 30000)
        XCTAssertEqual(FTPCommandBuilder.extendedPassivePort(from: FTPReply(code: 229, text: "Entering Extended Passive Mode (|||30001|)")), 30001)
        XCTAssertNil(FTPCommandBuilder.extendedPassivePort(from: FTPReply(code: 500, text: "EPSV not understood")))
    }

    func testRepliesMapToUserErrors() {
        XCTAssertEqual(FTPCommandBuilder.error(for: FTPReply(code: 530, text: "Login incorrect.")), .authenticationFailed)
        guard case .connectionFailed = FTPCommandBuilder.error(for: FTPReply(code: 530, text: "Non-anonymous sessions must use encryption.")) else {
            return XCTFail("Expected a hint to use FTPS")
        }
    }

    func testServerAddressParsesPastedURLs() {
        XCTAssertEqual(ServerAddress.parse(" sftp://deploy@public.example.com "), ServerAddress(protocolKind: .sftp, username: "deploy", host: "public.example.com"))
        XCTAssertEqual(ServerAddress.parse("ftpes://u%40corp@files.example.com/in/box"), ServerAddress(protocolKind: .ftps, username: "u@corp", host: "files.example.com", port: 21, path: "/in/box", implicitTLS: false))
        XCTAssertEqual(ServerAddress.parse("[2001:db8::1]:2222"), ServerAddress(host: "2001:db8::1", port: 2222))
        XCTAssertEqual(ServerAddress.parse("2001:db8::1"), ServerAddress(host: "2001:db8::1"))
        XCTAssertEqual(ServerAddress.parse("example.com:2121"), ServerAddress(host: "example.com", port: 2121))
    }

    func testValidatorRejectsHostsThatLookLikeOptions() {
        for host in ["-oProxyCommand=touch /tmp/x", "user@host", "host name", "sftp://host"] {
            let profile = ServerProfile(displayName: "Bad", host: host, protocolKind: .sftp, username: "u", authenticationMethod: .agent)
            XCTAssertThrowsError(try ServerProfileValidator.validate(profile), host)
        }
    }

    func testRoutingSendsFTPProfilesToFTPClient() async throws {
        let routing = ProtocolRoutingRemoteFileSystemClient(
            sftp: UnsupportedRemoteFileSystemClient(protocolKind: .sftp),
            ftp: UnsupportedRemoteFileSystemClient(protocolKind: .ftp)
        )
        let profile = ServerProfile(displayName: "FTP", host: "h", protocolKind: .ftps, username: "u", authenticationMethod: .none)

        do {
            _ = try await routing.connect(to: profile)
            XCTFail("Expected the stub to throw")
        } catch {
            XCTAssertEqual(error as? RemoteClientError, .unsupportedProtocol(.ftps))
        }
    }
}
