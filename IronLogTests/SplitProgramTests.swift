import XCTest
@testable import IronLog

final class SplitProgramTests: XCTestCase {
    func testEveryBundledSplitHasItsOwnCopy() {
        let library = ExerciseLibrary.bundled
        XCTAssertFalse(library.splits.isEmpty)
        for split in library.splits {
            let program = SplitProgram.describe(split, days: library.splitDays[split])
            XCTAssertEqual(program.name, split)
            XCTAssertNotEqual(program.systemImage, "square.grid.2x2", "\(split) should not fall back to the generic card")
            XCTAssertFalse(program.summary.isEmpty)
            XCTAssertFalse(program.cadence.isEmpty)
        }
    }

    func testUnknownSplitFallsBackToItsDayCount() {
        let days = [SplitDay(day: "A", muscles: ["chest"]), SplitDay(day: "B", muscles: ["back"])]
        let program = SplitProgram.describe("Bro Split", days: days)
        XCTAssertEqual(program.name, "Bro Split")
        XCTAssertEqual(program.systemImage, "square.grid.2x2")
        XCTAssertEqual(program.summary, "2 training days to rotate through")
        XCTAssertEqual(program.cadence, "2 days / week")

        let dayless = SplitProgram.describe("Kettlebell", days: nil)
        XCTAssertEqual(dayless.summary, "One session covers the whole plan")
        XCTAssertEqual(dayless.cadence, "Flexible")
    }

    func testAccessibilityIdentifiersAreStableSlugs() {
        XCTAssertEqual(SplitProgram.describe("PPL", days: nil).accessibilityIdentifier, "split-ppl")
        XCTAssertEqual(SplitProgram.describe("Upper/Lower", days: nil).accessibilityIdentifier, "split-upper-lower")
        XCTAssertEqual(SplitProgram.describe("Single Muscle", days: nil).accessibilityIdentifier, "split-single-muscle")
        XCTAssertEqual(SplitProgram.describe("  Odd -- Name! ", days: nil).accessibilityIdentifier, "split-odd-name")
    }
}
