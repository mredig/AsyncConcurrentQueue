import XCTest
@testable import AsyncConcurrentQueue

final class AsyncConcurrentQueueTests: XCTestCase {
    func testFutureTask() async throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(AsyncConcurrentQueue().text, "Hello, World!")
    }
}
