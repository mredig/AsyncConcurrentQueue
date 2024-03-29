import XCTest
@testable import AsyncConcurrentQueue

final class FutureTaskTests: XCTestCase {
    func testFutureTaskRun() async throws {
		let exp = expectation(description: "ran")
		let futureTask = FutureTask(priority: .low) {
			print("Waited until called")
			exp.fulfill()
			return true
		}

		futureTask.activate()
		await fulfillment(of: [exp], timeout: 10, enforceOrder: true)

		let value = try await futureTask.value
		XCTAssertTrue(value)
    }

	func testFutureTaskDetachedRun() async throws {
		let exp = expectation(description: "ran")
		let futureTask = FutureTask(priority: .low, detached: true) {
			print("Waited until called")
			exp.fulfill()
			return true
		}

		futureTask.activate()
		await fulfillment(of: [exp], timeout: 10, enforceOrder: true)

		let value = try await futureTask.value
		XCTAssertTrue(value)
	}

	func testFutureTaskCancellation() async throws {
		let exp = expectation(description: "ran")
		let canceller = FutureTask(
			operation: {
				return true
			},
			onCancellation: {
				exp.fulfill()
			})

		canceller.cancel()
		await fulfillment(of: [exp], timeout: 10, enforceOrder: true)

		let result = await canceller.result
		XCTAssertThrowsError(try result.get())
	}

	func testFutureTaskMultipleActivations() async throws {
		let exp = expectation(description: "ran")
		let futureTask = FutureTask(priority: .low) {
			print("Waited until called")
			exp.fulfill()
			return true
		}

		// will fail by way of multiple fulfills of expectations, if failed
		futureTask.activate()
		futureTask.activate()
		futureTask.activate()
		futureTask.activate()
		await fulfillment(of: [exp], timeout: 10, enforceOrder: true)
	}

	func testFutureTaskMultipleCancellations() async throws {
		let exp = expectation(description: "ran")
		let canceller = FutureTask(
			operation: {
				return true
			},
			onCancellation: {
				exp.fulfill()
			})

		// will fail by way of multiple fulfills of expectations, if failed
		canceller.cancel()
		canceller.cancel()
		canceller.cancel()
		canceller.cancel()
		await fulfillment(of: [exp], timeout: 10, enforceOrder: true)
	}
}
