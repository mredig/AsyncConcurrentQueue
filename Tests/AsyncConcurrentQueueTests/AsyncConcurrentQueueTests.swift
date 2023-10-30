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

//	func testCreateTasks() async throws {
//		let queue = AsyncQueue()
//
//		let startOrder = AtomicWrapper(value: [Int]())
//		let finishOrder = AtomicWrapper(value: [Int]())
//
//		let exp = expectation(description: "finished")
//		let iterations = 20
//		for i in 1...iterations {
//			let task = await queue.createTask {
//				startOrder.updateValue {
//					$0.append(i)
//				}
//				print("starting queued \(i)")
//				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
//				print("finishing queued \(i)")
//				return i
//			}
//
//			Task {
//				let value = try await task.value
//				finishOrder.updateValue {
//					$0.append(value)
//				}
//
//				if finishOrder.value.count == iterations {
//					exp.fulfill()
//				}
//			}
//		}
//
//		await fulfillment(of: [exp], timeout: 10)
//
//		XCTAssertEqual(finishOrder.value, startOrder.value)
//	}


//	func testConcurrentQueueItems2() async throws {
//		let queue = AsyncQueue()
//
//		let counter = AtomicWrapper(value: [Int]())
//
//		let iterations = 100
//		await queue.setMaximumConcurrentTasks(iterations / 10)
//
//		let checker = Task {
//			let maxTasks = await queue.maximumConcurrentTasks
//			var currentTasks = await queue.currentlyExecutingTasks
//			while counter.value.count < iterations {
//				guard
//					currentTasks < maxTasks
//				else { throw SimpleTestError(message: "More current tasks than maximum!") }
//				print(currentTasks)
//				try await Task.sleep(nanoseconds: 50)
//
//			}
//		}
//
//
//		for i in 1...iterations {
//			let value = try await queue.queueTask {
//				print("starting queued \(i)")
//				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
//				print("finishing queued \(i)")
//				return i
//			}
//			var arr = counter.value
//			arr.append(value)
//			counter.setValue(arr)
//		}
//
//		XCTAssertEqual(counter.value, counter.value.sorted())
//	}

	func testConcurrentQueueItems() async throws {
		let queue = AsyncConcurrentQueue()

		let setCounter = AtomicWrapper(value: Set<Int>())


		let exp = expectation(description: "finished")
		var mainSet: Set<Int> = []
		let iterations = 100
		setCounter.onValueChange { counter in
			let array = (0..<iterations).map { counter.value.contains($0) ? "|" : "_" }
			print(array.joined())
		}
		await queue.setMaximumConcurrentTasks(iterations / 10)
		for i in 0..<iterations {
			mainSet.insert(i)
			let task = await queue.queueTask {
				print("starting concurrent \(i)")
				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
				print("finishing concurrent \(i)")
				return i
			}

			Task {
				let value = try await task.value
				var set = setCounter.value
				set.insert(value)
				setCounter.setValue(set)

				if setCounter.value.count == iterations {
					exp.fulfill()
				}
			}

			print("Created concurrent task \(i)")
		}

		while setCounter.value.count < iterations {
			let current = await queue.currentlyExecutingTasks
			let max = await queue.maximumConcurrentTasks
			XCTAssertLessThanOrEqual(current, max)
			try await Task.sleep(nanoseconds: 1_000_000)
		}

		await fulfillment(of: [exp], timeout: 10)

		XCTAssertEqual(mainSet, setCounter.value)
	}

	func testConcurrentQueueItemsWithCancellations() async throws {
		let queue = AsyncConcurrentQueue()

		let setCounter = AtomicWrapper(value: Set<Int>())

		var mainSet: Set<Int> = []
		let iterations = 100
		await queue.setMaximumConcurrentTasks(iterations / 10)
		for i in 1...iterations {
			if i.isMultiple(of: 2) {
				mainSet.insert(i)
			}
			let task = await queue.queueTask {
				print("starting \(i)")
				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
				print("finishing \(i)")
				return i
			}

			Task {
				let value = try await task.value
				var set = setCounter.value
				set.insert(value)
				setCounter.setValue(set)
			}
			if i.isMultiple(of: 2) == false {
				task.cancel()
			}
		}

		while setCounter.value.count < mainSet.count {
			let current = await queue.currentlyExecutingTasks
			let max = await queue.maximumConcurrentTasks
			XCTAssertLessThanOrEqual(current, max)
			try await Task.sleep(nanoseconds: 1_000_000)
		}

		XCTAssertEqual(mainSet, setCounter.value)
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
