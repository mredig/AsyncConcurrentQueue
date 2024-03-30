import XCTest
import AsyncConcurrentQueue

final class AsyncConcurrentQueueTests: XCTestCase {
	func testQueueTasks() async throws {
		let queue = AsyncConcurrentQueue()

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
		let queue = AsyncConcurrentQueue()

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
		let queue = AsyncConcurrentQueue()

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
		let queue = AsyncConcurrentQueue()

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
		let queue = AsyncConcurrentQueue()

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

	/// Check that cancelling one queued item doesn't cancel others
	func testCancellations() async throws {
		let queue = AsyncConcurrentQueue(maximumConcurrentTasks: 15)

		let exp = expectation(description: "Finished")

		let results = AtomicWrapper(value: (oddCancellations: 0, evenSuccesses: 0))

		try await withThrowingTaskGroup(of: Void.self) { group in
			for index in 0..<200 {
				if index.isMultiple(of: 2) {
					group.addTask {
						try await queue.performTask {
							try await withTaskCancellationHandler(
								operation: {
									try await Task.sleep(nanoseconds: 20_000_000)
									try Task.checkCancellation()
									print("even success")
									results.updateValue {
										$0.evenSuccesses += 1
									}
								},
								onCancel: {
									print("even cancelled")
									results.updateValue {
										$0.evenSuccesses -= 1
									}
								})
						}
					}
				} else {
					group.addTask {
						let wrapper = AtomicWrapper<Task<Void, Error>?>(value: nil)
						let task = await queue.createTask {
							try await withTaskCancellationHandler(
								operation: {
									try await Task.sleep(nanoseconds: 20_000_000)
									wrapper.value?.cancel()
									try Task.checkCancellation()
									print("odd success")
									results.updateValue {
										$0.oddCancellations -= 1
									}								},
								onCancel: {
									print("odd cancelled")
									results.updateValue {
										$0.oddCancellations += 1
									}
								})
						}
						wrapper.updateValue({
							$0 = task
						})
					}
				}
			}

			try await group.waitForAll()
			exp.fulfill()
		}

		await fulfillment(of: [exp])

		XCTAssertEqual(100, results.value.evenSuccesses)
		XCTAssertEqual(100, results.value.oddCancellations)
	}

	/// Check that cancelling a parent task affects queued tasks
	func testCancellations2() async throws {
		let queue = AsyncConcurrentQueue(maximumConcurrentTasks: 15)

		let expA = expectation(description: "Finished")
		expA.assertForOverFulfill = false
		let expB = expectation(description: "Finished")

		let results = AtomicWrapper(value: (cancellations: 0, successes: 0, bSuccesses: 0))

		let sync = AtomicWrapper(value: 0)

		let taskA = Task {
			try await withThrowingTaskGroup(of: Void.self) { group in
				let fulfilled = AtomicWrapper(value: false)
				while fulfilled.value == false {
					group.addTask {
						try await queue.performTask {
							try await withTaskCancellationHandler(
								operation: {
									sync.updateValue {
										$0 += 1
									}
									defer {
										sync.updateValue {
											$0 -= 1
										}
									}
									try await Task.sleep(nanoseconds: 2_000_000)
									try Task.checkCancellation()
									print("testa success")
									results.updateValue {
										$0.successes += 1
									}
								},
								onCancel: {
									print("testa cancelled")
									results.updateValue {
										$0.cancellations += 1
									}
									expA.fulfill()
									fulfilled.updateValue({
										$0 = true
									})
								})
						}
					}
					try Task.checkCancellation()
				}

				try await group.waitForAll()
			}
		}

		Task {
			defer { expB.fulfill() }
			try await Task.sleep(nanoseconds: 500)
			try await withThrowingTaskGroup(of: Void.self) { group in
				for _ in 0..<200 {
					group.addTask {
						try await queue.performTask {
							try await withTaskCancellationHandler(
								operation: {
									try await Task.sleep(nanoseconds: 2_000_000)
									try Task.checkCancellation()
									print("testb success")
									results.updateValue {
										$0.successes += 1
										$0.bSuccesses += 1
									}
								},
								onCancel: {
									print("testb cancelled")
									results.updateValue {
										$0.cancellations += 1
									}
								})
						}
					}
				}

				try await group.waitForAll()
			}
		}

		_ = await Task {
			while true {
				try await Task.sleep(nanoseconds: 200)
				if sync.value > 1 {
					taskA.cancel()
					break
				}
			}
		}.result

		await fulfillment(of: [expA, expB])

		XCTAssertGreaterThan(results.value.successes, 0)
		XCTAssertGreaterThan(results.value.cancellations, 0)
		XCTAssertEqual(results.value.bSuccesses, 200)
	}

	func testPriorities() async throws {
		let arrWrapper = AtomicWrapper(value: [Double]())

		let queue = AsyncConcurrentQueue(maximumConcurrentTasks: 1)

		_ = await queue.createTask(label: "blocker", withPriority: 2) {
			try await Task.sleep(for: .seconds(3))
		}

		var lastValue: Double = 0
		for _ in 0..<1000 {
			let useLast = Int.random(in: 0..<50) == 0
			let value: Double
			defer { lastValue = value }
			if useLast {
				value = lastValue
			} else {
				value = Double.random(in: 0...9999)
			}
			_ = await queue.createTask(withPriority: value, {
				arrWrapper.updateValue {
					$0.append(value)
				}
			})
		}

		let exp = expectation(description: "finished")

		_ = await queue.createTask(withPriority: -10) {
			exp.fulfill()
		}

		await fulfillment(of: [exp], timeout: 10)

		let sorted = arrWrapper.value.sorted(by: { $0 > $1 })
		XCTAssertEqual(sorted, arrWrapper.value)
	}

	func testWaitForAll() async throws {
		let arrWrapper = AtomicWrapper(value: [Double]())

		let queue = AsyncConcurrentQueue(maximumConcurrentTasks: 1)

		_ = await queue.createTask(label: "blocker", withPriority: 2) {
			try await Task.sleep(for: .seconds(1))
		}

		for _ in 0..<1000 {
			_ = await queue.createTask({
				arrWrapper.updateValue {
					$0.append(0)
				}
			})
		}

		await queue.waitForAllTasks()

		XCTAssertEqual(arrWrapper.value.count, 1000)
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
