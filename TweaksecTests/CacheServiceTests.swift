import XCTest
@testable import Tweaksec

final class CacheServiceTests: XCTestCase {
    private var home: URL!
    private var service: CacheService!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("TweaksecTests-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        service = CacheService(home: home)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: home)
    }

    private func write(_ relativePath: String, bytes: Int = 4096) throws {
        let url = home.appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    private func target(_ id: String) -> CacheTarget {
        CacheTarget.defaults(home: home).first { $0.id == id }!
    }

    func testContentsSelectorListsChildrenAndKeepsFolder() throws {
        try write("Library/Developer/Xcode/DerivedData/App-abc/Build/a.o")
        try write("Library/Developer/Xcode/DerivedData/Other-def/info.plist")
        let derived = target("xcode.deriveddata")

        XCTAssertEqual(service.items(for: derived).count, 2)
        XCTAssertGreaterThan(service.size(of: derived), 0)

        let result = service.delete(derived, mode: .permanent)
        XCTAssertEqual(result.deletedCount, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertGreaterThan(result.freedBytes, 0)
        XCTAssertTrue(fm.fileExists(atPath: derived.revealURL.path))
        XCTAssertEqual(service.size(of: derived), 0)
    }

    func testPrefixedSelectorMatchesOnlyPrefix() throws {
        try write("Library/Caches/Google/AndroidStudio2024.1/x")
        try write("Library/Caches/Google/AndroidStudio2025.2/y")
        try write("Library/Caches/Google/Chrome/z")

        let names = service.items(for: target("android.studiocaches")).map(\.lastPathComponent).sorted()
        XCTAssertEqual(names, ["AndroidStudio2024.1", "AndroidStudio2025.2"])
    }

    func testProjectBuildFolders() throws {
        try write("Projects/MyApp/settings.gradle.kts")
        try write("Projects/MyApp/build/out.txt")
        try write("Projects/MyApp/app/build/out.txt")
        try write("Projects/MyApp/app/src/Main.kt")
        let project = CacheTarget.projectBuild(home.appendingPathComponent("Projects/MyApp"))

        let root = home.resolvingSymlinksInPath().path
        let items = service.items(for: project).map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: root, with: "") }.sorted()
        XCTAssertEqual(items, ["/Projects/MyApp/app/build", "/Projects/MyApp/build"])

        _ = service.delete(project, mode: .permanent)
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Projects/MyApp/app/src/Main.kt").path))
    }

    func testNonProjectFolderExposesNoBuildFolders() throws {
        try write("Projects/Other/build/out.txt")
        try write("Documents/build/out.txt")
        XCTAssertTrue(service.items(for: .projectBuild(home.appendingPathComponent("Projects"))).isEmpty)
        XCTAssertTrue(service.items(for: .projectBuild(home)).isEmpty)
    }

    func testSymlinkTargetIsNotFollowed() throws {
        try write("outside/keep.bin", bytes: 1_000_000)
        try fm.createDirectory(at: home.appendingPathComponent(".gradle/caches"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent(".gradle/caches/link"),
                                  withDestinationURL: home.appendingPathComponent("outside"))
        let gradle = target("android.gradle")

        XCTAssertEqual(service.size(of: gradle), 0)
        _ = service.delete(gradle, mode: .permanent)
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("outside/keep.bin").path))
    }

    func testMissingFolderIsEmpty() {
        XCTAssertTrue(service.items(for: target("android.avd")).isEmpty)
        XCTAssertEqual(service.delete(target("android.avd"), mode: .permanent).deletedCount, 0)
    }

    func testSafetyCheck() {
        XCTAssertTrue(service.isSafeToDelete(home.appendingPathComponent(".gradle/caches")))
        XCTAssertFalse(service.isSafeToDelete(home))
        XCTAssertFalse(service.isSafeToDelete(home.appendingPathComponent("Library")))
        XCTAssertFalse(service.isSafeToDelete(URL(fileURLWithPath: "/usr/local/bin")))
        XCTAssertFalse(service.isSafeToDelete(home.appendingPathComponent("a/../../../etc")))
    }
}
