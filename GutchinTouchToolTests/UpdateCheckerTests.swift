import XCTest
@testable import GutchinTouchTool

// MARK: - Mock network session

final class MockNetworkSession: NetworkSession, @unchecked Sendable {
    var dataHandler: ((URL) throws -> (Data, URLResponse))?
    var downloadHandler: ((URL) throws -> (URL, URLResponse))?

    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        guard let handler = dataHandler else {
            throw URLError(.badServerResponse)
        }
        return try handler(url)
    }

    func downloadFile(from url: URL) async throws -> (URL, URLResponse) {
        guard let handler = downloadHandler else {
            throw URLError(.badServerResponse)
        }
        return try handler(url)
    }
}

// MARK: - Version comparison tests

final class UpdateCheckerVersionTests: XCTestCase {

    func testNewerMajorVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.5.4"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("1.6.0", than: "1.5.4"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("1.5.5", than: "1.5.4"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.5.4", than: "1.5.4"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.4.0", than: "1.5.4"))
    }

    func testOlderPatchIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.5.3", than: "1.5.4"))
    }

    func testMalformedVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.5.4"))
    }

    func testMalformedLocalVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "abc"))
    }

    func testPartialVersionPadded() {
        // "2.0" should be treated as "2.0.0"
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.5.4"))
    }

    func testPartialLocalVersionPadded() {
        // "1.5" treated as "1.5.0" — older than "1.5.4"
        XCTAssertFalse(UpdateChecker.isNewer("1.5", than: "1.5.4"))
    }

    func testEmptyVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.5.4"))
    }

    func testBothZeroIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.0.0", than: "0.0.0"))
    }

    func testMajorBumpWithHigherLocal() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }
}

// MARK: - Update check tests (mocked network)

@MainActor
final class UpdateCheckerNetworkTests: XCTestCase {

    private func makeReleaseJSON(tag: String, dmgURL: String = "https://example.com/GutchinTouchTool.dmg") -> Data {
        """
        {
            "tag_name": "\(tag)",
            "assets": [
                {
                    "name": "GutchinTouchTool.dmg",
                    "browser_download_url": "\(dmgURL)"
                }
            ]
        }
        """.data(using: .utf8)!
    }

    private func makeReleaseJSONWithoutDMG(tag: String) -> Data {
        """
        {
            "tag_name": "\(tag)",
            "assets": [
                {
                    "name": "source.tar.gz",
                    "browser_download_url": "https://example.com/source.tar.gz"
                }
            ]
        }
        """.data(using: .utf8)!
    }

    func testCheckForUpdate_newerAvailable() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = self.makeReleaseJSON(tag: "v2.0.0")
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .available(let version, let url) = checker.status {
            XCTAssertEqual(version, "2.0.0")
            XCTAssertEqual(url.absoluteString, "https://example.com/GutchinTouchTool.dmg")
        } else {
            XCTFail("Expected .available, got \(checker.status)")
        }
    }

    func testCheckForUpdate_upToDate() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = self.makeReleaseJSON(tag: "v1.5.4")
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        XCTAssertEqual(checker.status, .upToDate)
    }

    func testCheckForUpdate_olderRelease() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = self.makeReleaseJSON(tag: "v1.4.0")
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        XCTAssertEqual(checker.status, .upToDate)
    }

    func testCheckForUpdate_noDMGAsset() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = self.makeReleaseJSONWithoutDMG(tag: "v2.0.0")
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .error(let msg) = checker.status {
            XCTAssertTrue(msg.contains("No DMG"))
        } else {
            XCTFail("Expected .error, got \(checker.status)")
        }
    }

    func testCheckForUpdate_networkError() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .error = checker.status {
            // Expected
        } else {
            XCTFail("Expected .error, got \(checker.status)")
        }
    }

    func testCheckForUpdate_malformedJSON() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = "not json at all".data(using: .utf8)!
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .error = checker.status {
            // Expected
        } else {
            XCTFail("Expected .error, got \(checker.status)")
        }
    }

    func testCheckForUpdate_emptyAssets() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = """
            { "tag_name": "v2.0.0", "assets": [] }
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .error(let msg) = checker.status {
            XCTAssertTrue(msg.contains("No DMG"))
        } else {
            XCTFail("Expected .error for empty assets, got \(checker.status)")
        }
    }

    func testCheckForUpdate_tagWithoutVPrefix() async {
        let mock = MockNetworkSession()
        mock.dataHandler = { _ in
            let data = self.makeReleaseJSON(tag: "2.0.0")
            return (data, HTTPURLResponse(url: UpdateChecker.releaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let checker = UpdateChecker(session: mock, currentVersion: "1.5.4")
        await checker.checkForUpdate()

        if case .available(let version, _) = checker.status {
            XCTAssertEqual(version, "2.0.0")
        } else {
            XCTFail("Expected .available, got \(checker.status)")
        }
    }
}

// MARK: - GitHubRelease model tests

final class GitHubReleaseTests: XCTestCase {

    func testVersionStripsVPrefix() {
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: """
        { "tag_name": "v1.5.4", "assets": [] }
        """.data(using: .utf8)!)
        XCTAssertEqual(release.version, "1.5.4")
    }

    func testVersionWithoutPrefix() {
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: """
        { "tag_name": "1.5.4", "assets": [] }
        """.data(using: .utf8)!)
        XCTAssertEqual(release.version, "1.5.4")
    }

    func testDmgURLFound() {
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: """
        {
            "tag_name": "v1.0.0",
            "assets": [
                { "name": "source.zip", "browser_download_url": "https://example.com/source.zip" },
                { "name": "GutchinTouchTool.dmg", "browser_download_url": "https://example.com/App.dmg" }
            ]
        }
        """.data(using: .utf8)!)
        XCTAssertEqual(release.dmgURL?.absoluteString, "https://example.com/App.dmg")
    }

    func testDmgURLNilWhenMissing() {
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: """
        {
            "tag_name": "v1.0.0",
            "assets": [
                { "name": "source.zip", "browser_download_url": "https://example.com/source.zip" }
            ]
        }
        """.data(using: .utf8)!)
        XCTAssertNil(release.dmgURL)
    }
}
