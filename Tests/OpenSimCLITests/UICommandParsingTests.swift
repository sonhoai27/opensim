import ArgumentParser
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class UICommandParsingTests: XCTestCase {
    func testScreenshotAndTap() throws {
        let shot = try XCTUnwrap(
            try OpenSimCommand.parseAsRoot(
                ["ui", "screenshot", "--out", "/tmp/a.png", "--scale", "0.5", "--json"]
            ) as? UIScreenshotCommand
        )
        XCTAssertEqual(shot.out, "/tmp/a.png")
        XCTAssertEqual(shot.scale, 0.5)

        let tap = try XCTUnwrap(
            try OpenSimCommand.parseAsRoot(
                ["ui", "tap", "--on", "id=fixture-primary-button", "--settle"]
            ) as? UITapCommand
        )
        XCTAssertEqual(tap.on, "id=fixture-primary-button")
        XCTAssertNoThrow(try tap.validate())

        XCTAssertThrowsError(
            try OpenSimCommand.parseAsRoot(
                ["ui", "tap", "--x", "1", "--y", "2", "--on", "id=a"]
            )
        )
        XCTAssertThrowsError(
            try OpenSimCommand.parseAsRoot(["ui", "tap", "--x", "1"])
        )
    }

    func testTreeFindWaitAct() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                try OpenSimCommand.parseAsRoot(["ui", "tree", "--max-depth", "10"]) as? UITreeCommand
            ).maxDepth,
            10
        )
        XCTAssertEqual(
            try XCTUnwrap(
                try OpenSimCommand.parseAsRoot(["ui", "find", "id=fixture-primary-button"]) as? UIFindCommand
            ).selector,
            "id=fixture-primary-button"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                try OpenSimCommand.parseAsRoot(["ui", "wait", "--on", "id=a", "--timeout-ms", "3000"]) as? UIWaitCommand
            ).timeoutMs,
            3000
        )
        let act = try XCTUnwrap(
            try OpenSimCommand.parseAsRoot(
                ["ui", "act", "--steps", "[{\"type\":\"tap\",\"on\":{\"identifier\":\"a\"}}]"]
            ) as? UIActCommand
        )
        XCTAssertNoThrow(try act.validatedSteps())

        let bad = try XCTUnwrap(
            try OpenSimCommand.parseAsRoot(["ui", "act", "--steps", "[]"]) as? UIActCommand
        )
        XCTAssertThrowsError(try bad.validatedSteps())
    }

    func testSelectorAndPointValidation() throws {
        XCTAssertNoThrow(try UICommandSupport.selectorJSON("id=a,label=Go"))
        XCTAssertThrowsError(try UICommandSupport.selectorJSON("label"))
        XCTAssertNoThrow(try UICommandSupport.pointJSON("1,2", label: "from"))
        XCTAssertThrowsError(try UICommandSupport.pointJSON("1", label: "from"))
        let tap = try XCTUnwrap(
            try OpenSimCommand.parseAsRoot(["ui", "tap", "--x", "1", "--y", "2"]) as? UITapCommand
        )
        XCTAssertNoThrow(try tap.validate())
    }
}
