import ArgumentParser
import XCTest
@testable import ManotifyKit

final class ParsingTests: XCTestCase {
    func testColors() {
        let red = RGBA(red: 1, green: 0, blue: 0)
        for form in ["ff0000", "#ff0000", "#F00", "f00", "255,0,0", "(255,0,0)", "rgb(255, 0, 0)"] {
            XCTAssertEqual(RGBA(argument: form), red, form)
        }
        XCTAssertEqual(RGBA(argument: "white"), RGBA(red: 1, green: 1, blue: 1))
        XCTAssertEqual(RGBA(argument: "00000000")?.alpha, 0)
        for bad in ["nope", "12", "256,0,0", "1,2", "1,2,3,4", "gggggg", ""] {
            XCTAssertNil(RGBA(argument: bad), bad)
        }
    }

    func testDurations() {
        XCTAssertEqual(parseDuration("90s"), 90)
        XCTAssertEqual(parseDuration("5m"), 300)
        XCTAssertEqual(parseDuration("2h"), 7200)
        XCTAssertEqual(parseDuration("1d"), 86400)
        XCTAssertEqual(parseDuration("12"), 12)
        for bad in ["", "0", "-5m", "m", "5x"] { XCTAssertNil(parseDuration(bad), bad) }
    }

    func testTimes() {
        XCTAssertEqual(parseClock("18:05"), DateComponents(hour: 18, minute: 5))
        for bad in ["24:00", "10:60", "10", "10:5"] { XCTAssertNil(parseClock(bad), bad) }
        XCTAssertNil(parseAt("2000-01-01 10:00"))
        XCTAssertEqual(parseAt("2999-01-02 03:04")?.year, 2999)
        XCTAssertEqual(parseEvery("tue@14:00")?.weekday, 3)
        XCTAssertNil(parseEvery("daily@09:30")?.weekday)
        XCTAssertEqual(parseEvery("09:30")?.hour, 9)
        XCTAssertNil(parseEvery("noday@09:30"))
    }

    func testSfIsNotSplitIntoShortFlags() throws {
        let send = try Send.parseAsRoot(["-t", "x", "-sf", "bell", "-c", "red", "-s", "none"]) as! Send
        XCTAssertEqual(send.icon.symbol, "bell")
        XCTAssertEqual(send.sound, "none")
        XCTAssertEqual(send.icon.color, RGBA(argument: "red"))
    }

    func testRootDefaultsToSend() throws {
        XCTAssertTrue(try Manotify.parseAsRoot(["Build done", "-sf", "hammer"]) is Send)
        XCTAssertTrue(try Manotify.parseAsRoot(["list"]) is List)
    }

    func testInvalidCombinationsAreRejected() {
        for arguments in [
            ["-t", "x", "-sf", "bell", "-i", "a.png"],
            ["-t", "x", "--wait", "--in", "5m"],
            ["-t", "x", "--in", "30s", "--repeat"],
            ["-t", "x", "--in", "5m", "--at", "10:00"],
            ["-t", "x", "--user-info", "{nope"],
            ["-t", "x", "-n", "../evil"],
        ] {
            XCTAssertThrowsError(try Send.parseAsRoot(arguments), "\(arguments)")
        }
    }

    func testActionParsing() {
        XCTAssertEqual(ActionSpec(argument: "yes:Yes: do it")?.title, "Yes: do it")
        XCTAssertEqual(ActionSpec(argument: "Yes")?.id, "Yes")
    }
}
