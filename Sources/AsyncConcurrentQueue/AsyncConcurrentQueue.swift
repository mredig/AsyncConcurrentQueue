import Foundation

public actor AsyncConcurrentQueue {
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

	typealias QueuedTask = Task<Void, Never>
	private var taskBarriers: [UUID: FutureTask<Void>] = [:]
	private var queuedTasks: [(id: UUID, task: QueuedTask)] = []

	public init() {}

	public func queueTaskWithResult<Success>(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) async throws -> Success {
		try await queueTask(priority: priority, operation: operation).value
	}
	
	/// Queues up a task. The task will be started immediately if `currentlyExecutingTasks` is fewer than `maximumConcurrentTasks`, otherwise it will wait in a queue in FIFO order.
	/// - Parameters:
	///   - priority: Priority of the task. Pass `nil` to use priority from `Task.currentPriority
	///   - operation: The operation to perform
	/// - Returns: A `Task<Success, Error>` whose value or result may be awaited.
	@discardableResult
	public func queueTask<Success>(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) -> Task<Success, Error> {

		let taskID = UUID()
		let barrier = FutureTask<Void>{}
		let inputTask = Task(priority: priority) {
			_ = await barrier.result
			return try await operation()
		}

		queuedTasks.append((taskID, Task { _ = await inputTask.result }))
		taskBarriers[taskID] = barrier

		bumpQueue()

		return inputTask
	}

	private func bumpQueue() {
		while
			currentlyExecutingTasks < maximumConcurrentTasks,
			let next = queuedTasks.first {

			queuedTasks.remove(at: 0)
			currentlyExecutingTasks += 1
			Task {
				_ = await next.task.result
				currentlyExecutingTasks -= 1
			}
			taskBarriers[next.id]?.activate()
			taskBarriers[next.id] = nil
		}
	}

	/**
	 Update the value of `maximumConcurrentTasks`. If provided with a value below `1`, it will be reset to `1`.
	 */
	public func setMaximumConcurrentTasks(_ value: Int) {
		maximumConcurrentTasks = value
	}
}

