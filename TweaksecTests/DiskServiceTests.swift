import XCTest
@testable import Tweaksec

final class DiskServiceTests: XCTestCase {
    func testBootVolumeInfo() throws {
        let info = try XCTUnwrap(DiskService.info(for: URL(fileURLWithPath: "/")))
        XCTAssertGreaterThan(info.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(info.availableBytes, 0)
        XCTAssertLessThanOrEqual(info.availableBytes, info.totalBytes)
        XCTAssert((0...1).contains(info.usedFraction))
    }

    func testMountedVolumesIncludesBoot() {
        XCTAssertFalse(DiskService.mountedVolumes().isEmpty)
    }

    func testUsedFractionHandlesZeroTotal() {
        let info = DiskInfo(volumeName: "x", volumeURL: URL(fileURLWithPath: "/"), totalBytes: 0, availableBytes: 0)
        XCTAssertEqual(info.usedFraction, 0)
    }
}
