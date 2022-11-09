# AsyncConcurrentQueue

A FIFO queuing system leveraging Swift's async/await structured concurrency. Also includes `FutureTask` which allows you to arbitrairily delay/start a task.

### Usage
```swift
import AsyncConcurrentQueue

// AsyncConcurrentQueue
Task {
	// initialize a new queue
	let queue = AsyncConcurrentQueue()
	
	// set how many tasks may run concurrently
	await queue.setMaximumConcurrentTasks(5)
	
	// feed it a bunch of tasks to perform.
	for i in 1...20 {
		let task = await queue.queueTask {
			print("starting \(i)")
			try await Task.sleep(for: .seconds(Double.random(in: 0.5...2)))
			print("finishing \(i)")
			return i
		}

		Task {
			let value = try await task.value
			print("Got \(value) from \(i)")
		}
	}
}

// FutureTask
Task {
	// create future task. Note that it does not run right away.
	let futureTask = FutureTask {
		print("Waited until called")
	}

	// create normal task for comparison. Note that it runs almost immediately.
	Task {
		print("Ran immediately")
	}

	// create a separate future task. It doesn't run right away, but also has a cancellation handler.
	let canceller = FutureTask(
		operation: {
			print("Will never run")
		},
		onCancellation: {
			print("Cancelled before activation")
		})

	// wait half a second
	try await Task.sleep(for: .seconds(0.5))
	// cancel the `canceller` task. The cancellation handler will run.
	canceller.cancel()

	// wait another couple seconds
	try await Task.sleep(for: .seconds(2))
	
	// activate the `futureTask`, allowing it to proceed now.
	futureTask.activate()
}
```
