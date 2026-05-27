@testable import DriftlineCore
import XCTest

final class EncryptedProfileExporterTests: XCTestCase {
    private let password = "secret"

    private func makeProfile(displayName: String) -> ServerProfile {
        ServerProfile(
            displayName: displayName,
            host: "example.com",
            port: 22,
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .agent,
            remoteDefaultPath: "/var/www",
            localDefaultPath: "/Users/test",
            notes: "test note",
            tags: ["prod"],
            isFavorite: false,
            groupName: nil,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    func testExportAndImportRoundTrip() throws {
        let profiles = [makeProfile(displayName: "Alpha"), makeProfile(displayName: "Beta")]
        let data = try EncryptedProfileExporter.export(profiles: profiles, password: self.password)
        let imported = try EncryptedProfileExporter.import(data: data, password: self.password)

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].displayName, "Alpha")
        XCTAssertEqual(imported[1].displayName, "Beta")
        XCTAssertEqual(imported[0].host, "example.com")
        XCTAssertEqual(imported[0].username, "deploy")
        XCTAssertEqual(imported[0].tags, ["prod"])
    }

    func testWrongPasswordThrows() throws {
        let profiles = [makeProfile(displayName: "Alpha")]
        let data = try EncryptedProfileExporter.export(profiles: profiles, password: self.password)

        XCTAssertThrowsError(try EncryptedProfileExporter.import(data: data, password: "wrong")) { error in
            XCTAssertEqual(error as? EncryptedProfileError, .wrongPassword)
        }
    }

    func testEmptyProfileListExportsAndImports() throws {
        let data = try EncryptedProfileExporter.export(profiles: [], password: self.password)
        let imported = try EncryptedProfileExporter.import(data: data, password: self.password)
        XCTAssertTrue(imported.isEmpty)
    }

    func testExportedDataIsValidJSON() throws {
        let profiles = [makeProfile(displayName: "Alpha")]
        let data = try EncryptedProfileExporter.export(profiles: profiles, password: self.password)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNotNil(json["salt"])
        XCTAssertNotNil(json["nonce"])
        XCTAssertNotNil(json["ciphertext"])
        XCTAssertEqual(json["profileCount"] as? Int, 1)
    }

    func testDifferentPasswordsProduceDifferentCiphertexts() throws {
        let profiles = [makeProfile(displayName: "Alpha")]
        let data1 = try EncryptedProfileExporter.export(profiles: profiles, password: "password-one")
        let data2 = try EncryptedProfileExporter.export(profiles: profiles, password: "password-two")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle1 = try decoder.decode(EncryptedProfileBundle.self, from: data1)
        let bundle2 = try decoder.decode(EncryptedProfileBundle.self, from: data2)
        XCTAssertNotEqual(bundle1.ciphertext, bundle2.ciphertext)
    }

    func testBandwidthThrottleDelayCalculation() {
        let throttle = BandwidthThrottle(bytesPerSecondLimit: 1_000_000)
        let delay = throttle.delay(bytesSent: 500_000, elapsed: 0.1)
        XCTAssertEqual(delay, 0.4, accuracy: 0.001)
    }
}
