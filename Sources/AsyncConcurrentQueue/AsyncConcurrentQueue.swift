import Foundation

public class AsyncConcurrentQueue {
	private let asyncLock = NSLock()
	private var continuations: [CheckedContinuation<Void, Never>] = []

	private var _maximumConcurrentTasks = 1

	/**
	 Defaults to `1`. Cannot be set lower than `1`. Doing so will reset it to `1`. Does what it says.

	 If set to a lower value, the queue does NOT cancel any running tasks, but will start no more until the threshold is appropriate.
	 */
	public private(set) var maximumConcurrentTasks: Int {
		get { _maximumConcurrentTasks }
		set {
			_maximumConcurrentTasks = max(1, newValue)
		}
	}

	/**
	 It is what it says.
	 */
	public private(set) var currentlyExecutingTasks = 0

	public init(maximumConcurrentTasks: Int = 1) {
		self._maximumConcurrentTasks = maximumConcurrentTasks
	}

	private func canIncrementCurrentTasks(andDoIt flag: Bool = false) -> Bool {
		asyncLock.lock()
		defer { asyncLock.unlock() }
		guard
			currentlyExecutingTasks < maximumConcurrentTasks
		else { return false }
		if flag {
			currentlyExecutingTasks += 1
			_bumpQueue()
		}
		return true
	}

	private func decrementCurrentTasks() {
		asyncLock.lock()
		defer { asyncLock.unlock() }
		guard
			currentlyExecutingTasks > 0
		else { fatalError("Called `decrementCurrentTasks` with no running tasks") }
		currentlyExecutingTasks -= 1
		_bumpQueue()
	}

	public func performTask<T>(label: String? = nil, _ task: () async throws -> T) async throws -> T {
		if canIncrementCurrentTasks(andDoIt: true) {
			defer { decrementCurrentTasks() }
			return try await task()
		} else {
			label.map { print("delaying \($0)") }
			async let delay: Void = withCheckedContinuation { continuation in
				appendToContinuations(continuation)
			}
			bumpQueue()
			await delay
			defer { decrementCurrentTasks() }
			try Task.checkCancellation()
			return try await task()
		}
	}

	public func createTask<T>(label: String? = nil, _ block: @escaping @Sendable () async throws -> T) async -> Task<T, Error> {
		if canIncrementCurrentTasks(andDoIt: true) {
			return Task {
				defer { decrementCurrentTasks() }
				let rVal = try await block()
				return rVal
			}
		} else {
			label.map { print("delaying \($0)") }
			let delayTask = Task {
				await withCheckedContinuation { continuation in
					appendToContinuations(continuation)
				}
			}
			let finalTask = Task {
				_ = await delayTask.result
				defer { decrementCurrentTasks() }
				try Task.checkCancellation()
				let rVal = try await block()
				return rVal
			}

			bumpQueue()
			return finalTask
		}
	}

	private func appendToContinuations(_ continuation: CheckedContinuation<Void, Never>) {
		asyncLock.lock()
		defer { asyncLock.unlock() }
		continuations.append(continuation)
	}

	private func bumpQueue() {
		asyncLock.lock()
		defer { asyncLock.unlock() }
		_bumpQueue()
	}
	private func _bumpQueue() {
		guard
			currentlyExecutingTasks < maximumConcurrentTasks,
			let continuation = continuations.first
		else { return }

		continuations.removeFirst()
		continuation.resume()
		currentlyExecutingTasks += 1
	}

	/**
	 Update the value of `maximumConcurrentTasks`. If provided with a value below `1`, it will be reset to `1`.
	 */
	public func setMaximumConcurrentTasks(_ value: Int) {
		asyncLock.lock()
		defer { asyncLock.unlock() }
		maximumConcurrentTasks = value
		_bumpQueue()
	}
}
