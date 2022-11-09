import XCTest
@testable import AsyncConcurrentQueue

final class AsyncConcurrentQueueTests: XCTestCase {

    func testQueueItems() async throws {
		let queue = AsyncConcurrentQueue()

		let counter = AtomicWrapper(value: [Int]())

//		await queue.setMaximumConcurrentTasks(10)
		let iterations = 20
		for i in 1...iterations {
			let task = await queue.queueTask {
				print("starting \(i)")
				try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.01...0.1) * 1_000_000_000))
				print("finishing \(i)")
				return i
			}

			Task {
				let value = try await task.value
				var arr = counter.value
				arr.append(value)
				counter.setValue(arr)
			}
		}

		while counter.value.count < iterations {
			try await Task.sleep(nanoseconds: 1_000_000)
		}

		XCTAssertEqual(counter.value, counter.value.sorted())
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
