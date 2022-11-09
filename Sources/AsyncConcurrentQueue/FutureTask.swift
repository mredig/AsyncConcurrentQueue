import Foundation

/**
 Allows for arbitrary task delays. Useful when you don't have a specific `Task` to `await` and instead need a method to directly start a task upon some event.
 */
public class FutureTask<Success: Sendable>: @unchecked Sendable {
	private var task: Task<Success, Error>!
	private var continuation: CheckedContinuation<Void, Error>?

	private var hasActivated = false
	private var hasRun = false
	public var isCancelled: Bool { task.isCancelled }

	private let lock = NSLock()

	private let onCancellation: () -> Void

	/// The task’s result.
	public var value: Success {
		get async throws {
			try await task.value
		}
	}

	/// If the task succeeded, .success with the task’s result as the associated value; otherwise, .failure with the error as the associated value.
	public var result: Result<Success, Error> {
		get async {
			await task.result
		}
	}


	/// Creates a new `FutureTask`
	/// - Parameters:
	///   - priority: Priority of the task. Pass `nil` to use priority from `Task.currentPriority
	///   - operation: The operation to perform
	///   - onCancellation: The operation to perform upon cancellation
	public init(
		priority: TaskPriority? = nil,
		operation: @escaping () async throws -> Success,
		onCancellation: @escaping () -> Void = {}) {
			self.onCancellation = onCancellation
			lock.lock()
			defer { lock.unlock() }
			let buffer = Task(priority: priority) {
				try await withCheckedThrowingContinuation {
					setContinuation($0)
				}

				return try await operation()
			}

			self.task = buffer
		}

	private func setContinuation(_ cont: CheckedContinuation<Void, Error>) {
		lock.lock()
		defer { lock.unlock() }
		guard self.continuation == nil else { return }
		self.continuation = cont

		if hasActivated && hasRun == false {
			_activate()
		}
	}

	/**
	 The `FutureTask` lays dormant until activated or cancelled. This is a contract that `activate()` or `cancel()` is eventually called. If neither are ever called, this is considered an error equal to never calling a Continuation in `withCheckedThrowingContinuation`, etc.

	 Calling `activate()` more than once (or after `cancel()`) has no effect, but it's better not to. (Ideally all references to the task have released and it can be released from memory)
	 */
	public func activate() {
		lock.lock()
		defer { lock.unlock() }
		_activate()
	}

	private func _activate() {
		guard
			hasActivated == false || hasRun == false
		else { return }
		hasActivated = true
		guard
			hasRun == false,
			let continuation,
			isCancelled == false
		else { return }
		continuation.resume()
		hasRun = true
	}

	/**
	 The `FutureTask` lays dormant until activated or cancelled. This is a contract that `activate()` or `cancel()` is eventually called. If neither are ever called, this is considered an error equal to never calling a Continuation in `withCheckedThrowingContinuation`, etc.

	 Calling `cancel()` more than once (or after `activate()`) has no effect, but it's better not to. (Ideally all references to the task have released and it can be released from memory)
	 */
	public func cancel() {
		lock.lock()
		defer { lock.unlock() }
		guard
			isCancelled == false,
			hasRun == false
		else { return }
		task.cancel()
		continuation?.resume(throwing: CancellationError())
		onCancellation()
	}
}
