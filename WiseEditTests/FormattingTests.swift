import XCTest
@testable import WiseEdit

final class FormattingTests: XCTestCase {
    func testTimecodeUnderAnHour() {
        XCTAssertEqual(75.0.timecodeString, "1:15")
        XCTAssertEqual(5.0.timecodeString, "0:05")
    }

    func testTimecodeOverAnHour() {
        XCTAssertEqual(3725.0.timecodeString, "1:02:05")
    }

    func testTimecodeNegativeIsZero() {
        XCTAssertEqual((-4.0).timecodeString, "0:00")
    }
}
