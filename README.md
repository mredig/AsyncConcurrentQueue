# AsyncConcurrentQueue

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmredig%2FAsyncConcurrentQueue%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mredig/AsyncConcurrentQueue) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmredig%2FAsyncConcurrentQueue%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mredig/AsyncConcurrentQueue)

A mostly\* FIFO queuing system leveraging Swift's async/await structured concurrency. Also includes `FutureTask` which allows you to arbitrairily delay/start a task.

<style>.foootnote { font-size: 0.6em; }</style>
<span class="foootnote">\*mostly: async/await is utilized to append tasks to the queue, so, if several tasks are appended in quick succession, we are at the whims of async/await to order things correctly. However, the start\*\* order is guaranteed once the task is added.</span>

<span class="foootnote">\*\*started: if the queue allows multiple concurrent tasks, shorter tasks started after a longer task will likely finish prior to the longer, first task.</span>

### Usage
```swift
import AsyncConcurrentQueue

// AsyncConcurrentQueue
Task {
	// initialize a new queue
	let queue = AsyncConcurrentQueue()
	
	// set how many tasks may run concurrently
	queue.setMaximumConcurrentTasks(5)
	
	// feed it a bunch of tasks to perform.
	for i in 1...20 {
		let task = await queue.createTask {
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
### A note on FIFO

The current implementation is pretty poor at handling FIFO when tasks are added in quick succession. My future plan is to add sync methods for adding tasks, taking in async closures (similar to now), but to revamp the internals to just immediately append the tasks to an array. This would solidify the order. THEN the async system would one by one retrieve the first element of the array to create the async tasks. (That's the plan, at least. There will be several challenges, like maintaining the generic return value of the queued tasks, but that's a problem for Monday Michael.)
