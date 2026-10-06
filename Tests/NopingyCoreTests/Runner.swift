import Foundation

// A dependency-free assertion runner works with Apple's Command Line Tools,
// which do not include the XCTest framework from full Xcode.
var failureCount = 0
var assertionCount = 0
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failureCount += 1
    print("FAIL \(file):\(line): \(message)")
}
func assertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertionCount += 1
    do { let a = try left(); let b = try right(); if a != b { fail("\(a) != \(b) \(message)", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func assertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertionCount += 1
    do { if try !value() { fail("Expected true \(message)", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func assertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { assertTrue(try !value(), file: file, line: line) }
func assertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { assertTrue(value() != nil, file: file, line: line) }
func assertLessThan<T: Comparable>(_ left: @autoclosure () -> T, _ right: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { assertTrue(left() < right(), file: file, line: line) }
func assertThrows<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertionCount += 1
    do { _ = try value(); fail("Expected an error \(message)", file: file, line: line) } catch { }
}

@main enum CheckRunner {
    static func main() async {
        let checks = CoreTests()
        do {
            try checks.testTargetsAndIPv6Ports()
            checks.testRejectsInvalidOrExecutableInputs()
            try checks.testBulkAliasCommentsAndAtomicFailure()
            checks.testPingReplyLossAndErrorClassification()
            checks.testStatisticsAcrossRepliesLossAndErrors()
            checks.testSettingsClampingAndCSV()
            try checks.testStateRoundTripAndCorruptionPreserved()
            try checks.testPingArgumentsMatchMacOS()
            try await checks.testCommandDeadlineAndCancellation()
        } catch { fail(error.localizedDescription) }
        print("9 check groups · \(assertionCount) assertions · \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
