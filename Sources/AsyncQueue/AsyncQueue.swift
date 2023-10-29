import Foundation

public actor AsyncQueue {
	private let continuationsLock = NSLock()
//	private var continuations: [CheckedContinuation<Void, Error>] = []
	private let continuations: ReferenceArray<CheckedContinuation<Void, Never>> = []

	private var _maximumConcurrentTasks = 1

	/**
	 Defaults to `1`. Cannot be set lower than `1`. Doing so will reset it to `1`. Does what it says.

	 If set to a lower value, the queue does NOT cancel any running tasks, but will start no more until the threshold is appropriate.
	 */
	public private(set) var maximumConcurrentTasks: Int {
		get { _maximumConcurrentTasks }
		set {
			_maximumConcurrentTasks = max(1, newValue)
			bumpQueue()
		}
	}

	/**
	 It is what it says.
	 */
	public private(set) var currentlyExecutingTasks = 0 {
		didSet {
			bumpQueue()
		}
	}

	public init(maximumConcurrentTasks: Int = 1) {
		self._maximumConcurrentTasks = maximumConcurrentTasks
	}

	public func queueTask<T>(_ task: () async throws -> T) async rethrows -> T {
		if currentlyExecutingTasks < maximumConcurrentTasks {
			return try await _doTheQueueTask(task)
		} else {
			async let delay: Void = withCheckedContinuation { continuation in
				appendToContinuations(continuation)
			}
			bumpQueue()
			await delay
			return try await _doTheQueueTask(task)
		}
	}

	private func _doTheQueueTask<T>(_ task: () async throws -> T) async rethrows -> T {
		currentlyExecutingTasks += 1
		defer { currentlyExecutingTasks -= 1 }
		return try await task()
	}

	public func createTask<T>(_ block: @escaping @Sendable () async throws -> T) async -> Task<T, Error> {
		if currentlyExecutingTasks < maximumConcurrentTasks {
			currentlyExecutingTasks += 1
			let finalTask = Task {
				try await block()
			}
			Task {
				_ = await finalTask.result
				currentlyExecutingTasks -= 1
			}
			return finalTask
		} else {
			let delayTask = Task {
				await withCheckedContinuation { continuation in
					appendToContinuations(continuation)
				}
			}
			let finalTask = Task {
				_ = await delayTask.result
				return try await _doTheQueueTask(block)
			}

			bumpQueue()
			return finalTask
		}
	}

	nonisolated
	private func appendToContinuations(_ continuation: CheckedContinuation<Void, Never>) {
		continuationsLock.lock()
		continuations.array.append(continuation)
		continuationsLock.unlock()
	}

	private func bumpQueue() {
		if currentlyExecutingTasks < maximumConcurrentTasks {
			continuationsLock.lock()
			if let continuation = continuations.array.first {
				continuations.array.removeFirst()
				continuationsLock.unlock()
				continuation.resume()
			} else {
				continuationsLock.unlock()
			}
		}
	}

	/**
	 Update the value of `maximumConcurrentTasks`. If provided with a value below `1`, it will be reset to `1`.
	 */
	public func setMaximumConcurrentTasks(_ value: Int) {
		maximumConcurrentTasks = value
	}

	private class ReferenceArray<Element>: ExpressibleByArrayLiteral {
		var array: [Element]

		init(array: [Element]) {
			self.array = array
		}

		convenience init(arrayLiteral elements: Element...) {
			self.init(array: elements)
		}
	}
}
