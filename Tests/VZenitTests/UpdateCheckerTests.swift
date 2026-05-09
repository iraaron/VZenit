// UpdateCheckerTests.swift
// VZenit — covers the pure-logic bits of UpdateChecker (version compare, tag prefix).

import XCTest
@testable import VZenit

final class UpdateCheckerTests: XCTestCase {

    // MARK: - stripVPrefix

    func testStripVPrefixWithLeadingV() {
        XCTAssertEqual(UpdateChecker.stripVPrefix("v0.0.1"), "0.0.1")
        XCTAssertEqual(UpdateChecker.stripVPrefix("v1.2.3"), "1.2.3")
    }

    func testStripVPrefixWithoutLeadingV() {
        XCTAssertEqual(UpdateChecker.stripVPrefix("0.0.1"), "0.0.1")
        XCTAssertEqual(UpdateChecker.stripVPrefix("1.2.3"), "1.2.3")
    }

    // MARK: - compareVersions

    func testCompareEqualVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("0.0.1", "0.0.1"), .orderedSame)
    }

    func testCompareNewerByPatch() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.0.2", "0.0.1"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.0.1", "0.0.2"), .orderedAscending)
    }

    func testCompareNewerByMinor() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.0", "0.0.99"), .orderedDescending)
    }

    func testCompareNewerByMajor() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "0.99.99"), .orderedDescending)
    }

    /// Numeric comparison (vs lexicographic) — "0.0.10" must beat "0.0.2".
    func testCompareNumericallyNotLexicographically() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.0.10", "0.0.2"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.0.2", "0.0.10"), .orderedAscending)
    }

    func testCompareDifferentLengths() {
        // Missing components should be treated as 0.
        XCTAssertEqual(UpdateChecker.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.1", "1.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1", "1.0.1"), .orderedAscending)
    }
}
