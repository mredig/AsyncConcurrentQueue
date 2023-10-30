import XCTest
@testable import AsyncConcurrentQueue
import AsyncQueue

final class AsyncConcurrentQueueTests: XCTestCase {
	func testQueueTasks() async throws {
		let queue = AsyncQueue()

		let startCounter = AtomicWrapper(value: [Int]())
		let finishCounter = AtomicWrapper(value: [Int]())
		let exp = expectation(description: "finished")

		let iterations = 20

		for i in 1...iterations {
			let valueTask = Task {
				try await queue.performTask {
					print("starting queued \(i)")
					startCounter.updateValue {
						$0.append(i)
					}
					try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
					print("finishing queued \(i)")
					XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
					return i
				}
			}
			XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)

			Task {
				XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
				let value = try await valueTask.value
				finishCounter.updateValue {
					$0.append(value)
				}
				if finishCounter.value.count == iterations {
					exp.fulfill()
				}
			}
		}

		await fulfillment(of: [exp])

		XCTAssertEqual(startCounter.value, finishCounter.value)
	}

	func testConcurrentQueueTasks() async throws {
		let queue = AsyncQueue()

		let iterations = 20
		queue.setMaximumConcurrentTasks(4)

		try await withThrowingTaskGroup(of: Int.self) { group in
			for i in 1...iterations {
				group.addTask {
					try await queue.performTask(label: "\(i)") {
						print("starting queued \(i)")
						try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
						print("finishing queued \(i)")
						return i
					}
				}

				XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
			}

			try await group.waitForAll()
		}
	}

	func testCreateTasks() async throws {
		let queue = AsyncQueue()

		let startCounter = AtomicWrapper(value: [Int]())
		let finishCounter = AtomicWrapper(value: [Int]())
		let exp = expectation(description: "finished")

		let iterations = 20

		for i in 1...iterations {
			let valueTask = await queue.createTask {
				print("starting queued \(i)")
				startCounter.updateValue {
					$0.append(i)
				}
				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
				print("finishing queued \(i)")
				XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
				return i
			}

			XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)

			Task {
				XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
				let value = try await valueTask.value
				finishCounter.updateValue {
					$0.append(value)
				}
				if finishCounter.value.count == iterations {
					exp.fulfill()
				}
			}
		}

		await fulfillment(of: [exp])

		XCTAssertEqual(startCounter.value, finishCounter.value)
	}

	func testCreateConcurrentTasks() async throws {
		let queue = AsyncQueue()

		let iterations = 20
		queue.setMaximumConcurrentTasks(4)

		try await withThrowingTaskGroup(of: Int.self) { group in
			for i in 1...iterations {
				group.addTask {
					let task = await queue.createTask(label: "\(i)") {
						print("starting queued \(i)")
						try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
						print("finishing queued \(i)")
						return i
					}

					return try await task.value
				}

				XCTAssertLessThanOrEqual(queue.currentlyExecutingTasks, queue.maximumConcurrentTasks)
			}

			try await group.waitForAll()
		}
	}

	func testConcurrentQueueItemsWithCancellations() async throws {
		let queue = AsyncQueue()

		let setCounter = AtomicWrapper(value: Set<Int>())

		var cancelSet: Set<Int> = []
		let exp = expectation(description: "finished")
		let iterations = 100
		queue.setMaximumConcurrentTasks(iterations / 10)
		for i in 1...iterations {
			if i.isMultiple(of: 2) {
				cancelSet.insert(i)
			}
			print("iteration: \(i)")
			let task = await queue.createTask {
				print("starting \(i)")
				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
				print("finishing \(i)")
				return i
			}

			Task {
				defer {
					if i == iterations {
						exp.fulfill()
					}
				}
				let value = try await task.value
				setCounter.updateValue {
					$0.insert(value)
				}
			}
			if i.isMultiple(of: 2) == false {
				task.cancel()
			}
		}

		await fulfillment(of: [exp])

		// with this test, it's possible for the cancellation to occur after the task finished,
		// however, it should be seldom. This allows for up to 5 failures, but most must work to count as a success
		XCTAssertLessThanOrEqual(cancelSet.symmetricDifference(setCounter.value).count, 5)
	}
}

class AtomicWrapper<Element>: @unchecked Sendable {
	private(set) var value: Element {
		didSet {
			blocks.forEach { $0(self) }
		}
	}

	private let lock = NSLock()

	private var blocks: [(AtomicWrapper<Element>) -> Void] = []

	init(value: Element) {
		self.value = value
	}

	func setValue(_ value: Element) {
		lock.lock()
		defer { lock.unlock() }

		self.value = value
	}

	func updateValue(_ block: (inout Element) -> Void) {
		lock.lock()
		defer { lock.unlock() }

		block(&self.value)
	}

	func onValueChange(_ block: @escaping (AtomicWrapper<Element>) -> Void) {
		blocks.append(block)
	}
}

extension AtomicWrapper where Element == Int {
	func iterate() {
		lock.lock()
		defer { lock.unlock() }

		value += 1
	}
}

struct SimpleTestError: Error {
	let message: String
}
