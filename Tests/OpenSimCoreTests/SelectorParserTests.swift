import XCTest
@testable import OpenSimCore

final class SelectorParserTests: XCTestCase {
    func testParsesQuotedAndEscapedValues() throws {
        let selector = try SelectorParser.parse("role=button, label=\"Sign in, now\"")
        XCTAssertEqual(selector.role, "button")
        XCTAssertEqual(selector.label, "Sign in, now")
        XCTAssertEqual(try SelectorParser.parse("label=Hello\\, world").label, "Hello, world")
    }

    func testRejectsInvalidSelectors() {
        XCTAssertThrowsError(try SelectorParser.parse("foo=bar"))
        XCTAssertThrowsError(try SelectorParser.parse("label="))
        XCTAssertThrowsError(try SelectorParser.parse("id=a,id=b"))
    }

    func testPointAndMatcher() throws {
        XCTAssertEqual(try PointParser.parse("12.5,-4", label: "from"), Point(x: 12.5, y: -4))
        XCTAssertThrowsError(try PointParser.parse(x: "10", y: nil))
        let element = UIElement(id: "e", role: "button", label: "Primary Action", identifier: "fixture-primary-button", value: nil, frame: Rect(x: 10, y: 20, width: 100, height: 44), enabled: true, selected: false, children: [])
        XCTAssertTrue(UIElementMatcher.matches(element, selector: ElementSelector(identifier: "fixture-primary-button")))
        XCTAssertFalse(UIElementMatcher.matches(element, selector: ElementSelector(role: "staticText")))
        XCTAssertEqual(UIElementMatcher.find(in: element, selector: ElementSelector(text: "primary")).count, 1)
    }
}
