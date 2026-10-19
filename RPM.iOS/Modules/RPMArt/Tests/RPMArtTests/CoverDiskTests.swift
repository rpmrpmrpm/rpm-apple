import Testing
import Foundation
@testable import RPMArt
import RPMDesign

private func scratch() -> URL {
    let at = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rpm-art-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: at, withIntermediateDirectories: true)
    return at
}

private let sleeve = Pictures.jpeg(field: RGB(120, 40, 160), edge: 200)

@Test func aPictureKeptIsAPictureFound() async {
    let disk = CoverDisk(directory: scratch())

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)

    #expect(await disk.picture(albumKey: "abc123", stamp: 7) == sleeve)
}

/// **The stamp is why a cache of covers works at all.** A cover replaced on another machine uses
/// the same address as the one already here. Only the version tells them apart.
@Test func anOlderVersionIsNotTheOneAskedFor() async {
    let disk = CoverDisk(directory: scratch())

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)

    #expect(await disk.picture(albumKey: "abc123", stamp: 8) == nil)
}

/// For a phone with no signal. A lookup without a stamp returns any stored version, because an
/// older cover is better than no picture.
@Test func anyVersionIsBetterThanNoPicture() async {
    let disk = CoverDisk(directory: scratch())

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)

    #expect(await disk.picture(albumKey: "abc123") == sleeve)
}

@Test func aRecordNobodyHasKeptIsNothing() async {
    let disk = CoverDisk(directory: scratch())

    #expect(await disk.picture(albumKey: "nothing") == nil)
    #expect(await disk.picture(albumKey: "nothing", stamp: 1) == nil)
}

/// A record has one cover. Keeping both versions would store a second copy of every cover that has
/// ever been corrected.
@Test func replacingASleeveDoesNotKeepTheOldOne() async {
    let at = scratch()
    let disk = CoverDisk(directory: at)

    let corrected = Pictures.jpeg(field: RGB(30, 160, 90), edge: 200)

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)
    await disk.hold(albumKey: "abc123", stamp: 9, corrected)

    #expect(await disk.picture(albumKey: "abc123", stamp: 9) == corrected)
    #expect(await disk.picture(albumKey: "abc123", stamp: 7) == nil)

    let files = try! FileManager.default.contentsOfDirectory(atPath: at.path)
    #expect(files.filter { $0.hasSuffix(".img") }.count == 1, "left \(files)")
}

// ── the directory is its own index ──

/// **Why there is no ledger file.** A ledger can list a picture that has been removed from disk.
/// A directory listing cannot. This test opens a new `CoverDisk` on the same directory, as a
/// relaunched phone app would.
@Test func aNewLaunchFindsWhatTheLastOneKept() async {
    let at = scratch()

    await CoverDisk(directory: at).hold(albumKey: "abc123", stamp: 7, sleeve)

    let afterRelaunch = CoverDisk(directory: at)
    #expect(await afterRelaunch.picture(albumKey: "abc123", stamp: 7) == sleeve)
}

/// iOS may empty the caches at any time, and it does not ask first. A listing can still show a
/// picture that has been deleted. The lookup must then return nil instead of throwing.
@Test func aPictureTakenAwayUnderneathIsSimplyGone() async {
    let at = scratch()
    let disk = CoverDisk(directory: at)

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)
    try? FileManager.default.removeItem(at: at.appendingPathComponent("abc123-7.img"))

    #expect(await disk.picture(albumKey: "abc123", stamp: 7) == nil)
}

/// An interrupted write leaves a partial file beside the name it was going to use. Nothing may
/// read that file as a picture.
@Test func aHalfWrittenFileIsNotACover() async {
    let at = scratch()
    try! Data([0xFF, 0xD8]).write(to: at.appendingPathComponent("abc123-7.img.part"))

    #expect(await CoverDisk(directory: at).picture(albumKey: "abc123", stamp: 7) == nil)
}

/// Two versions of one record on disk (an eviction that stopped halfway) resolve to the newer one.
/// The older file is removed at once.
@Test func aRecordLeftWithTwoVersionsKeepsTheNewer() async {
    let at = scratch()
    let corrected = Pictures.jpeg(field: RGB(30, 160, 90), edge: 200)

    try! sleeve.write(to: at.appendingPathComponent("abc123-7.img"))
    try! corrected.write(to: at.appendingPathComponent("abc123-9.img"))

    let disk = CoverDisk(directory: at)
    #expect(await disk.picture(albumKey: "abc123") == corrected)

    let files = try! FileManager.default.contentsOfDirectory(atPath: at.path)
    #expect(files == ["abc123-9.img"], "left \(files)")
}

@Test func whichRecordsAreHeldIsOneQuestionRatherThanOnePerRecord() async {
    let disk = CoverDisk(directory: scratch())

    await disk.hold(albumKey: "aaa", stamp: 1, sleeve)
    await disk.hold(albumKey: "bbb", stamp: 1, sleeve)

    #expect(await disk.held(["aaa", "bbb", "ccc"]) == ["aaa", "bbb"])
}

// ── the caps ──

@Test func aCacheDoesNotGrowWithoutEnd() async {
    let at = scratch()
    let disk = CoverDisk(directory: at, mostFiles: 3, mostBytes: .max)

    for i in 0..<6 {
        await disk.hold(albumKey: "key\(i)", stamp: 1, sleeve)
    }

    let files = try! FileManager.default.contentsOfDirectory(atPath: at.path)
        .filter { $0.hasSuffix(".img") }
    #expect(files.count <= 3, "kept \(files.count)")

    // The most recent cover is one of the covers that were kept.
    #expect(await disk.picture(albumKey: "key5", stamp: 1) == sleeve)
}

/// A file count alone is not a useful limit. Three thousand thumbnails weigh very little, while
/// two hundred scans can weigh a quarter of a gigabyte. The byte limit must apply as well.
@Test func theWeightIsAlsoABound() async {
    let at = scratch()
    let disk = CoverDisk(directory: at, mostFiles: .max, mostBytes: sleeve.count * 2)

    for i in 0..<6 {
        await disk.hold(albumKey: "key\(i)", stamp: 1, sleeve)
    }

    let files = try! FileManager.default.contentsOfDirectory(atPath: at.path)
        .filter { $0.hasSuffix(".img") }
    #expect(files.count <= 3, "kept \(files.count)")
}

/// Signing out, then signing in as another person. A phone that is handed on must not keep the
/// last person's record collection.
@Test func everythingCanBeGivenBack() async {
    let at = scratch()
    let disk = CoverDisk(directory: at)

    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)
    await disk.empty()

    #expect(await disk.picture(albumKey: "abc123", stamp: 7) == nil)
    #expect(!FileManager.default.fileExists(atPath: at.path))
}

@Test func aCacheEmptiedStillWorks() async {
    let at = scratch()
    let disk = CoverDisk(directory: at)

    await disk.empty()
    await disk.hold(albumKey: "abc123", stamp: 7, sleeve)

    #expect(await disk.picture(albumKey: "abc123", stamp: 7) == sleeve)
}
