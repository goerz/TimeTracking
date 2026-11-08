// StepQueue: the agent's loops and request handler, one step at a time
// (activity_tracking.md §2.1, §5).

import Foundation

/// Runs the agent's steps one at a time. A tick that is due, or asked for
/// by an event, runs before the next queued step; tick requests that
/// arrive while a step runs share one tick after it. Queued steps run in
/// arrival order, and a rebuild pass runs only when nothing else waits, so
/// a rebuild backlog never delays a tick.
///
/// Asking for work never waits: it starts the queue if it is idle. The
/// queue gives the main actor up after every step, so the socket and the
/// system events are served while a backlog runs.
@MainActor
final class StepQueue {
    /// A queued step; `key` drops a second request of the same step while
    /// the first waits; `cancel` runs instead of `run` when the agent stops.
    struct Step {
        var key: String
        var run: () async -> Void
        var cancel: (() -> Void)?
    }

    private var steps: [Step] = []
    private var tickRequested = false
    private var running = false
    private(set) var isStopping = false
    /// Callers of `drain()` waiting for the running drain to finish.
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let tick: () async -> Void
    private let tickIsDue: () -> Bool
    /// One rebuild pass; `false` when no date waits (or the loop waits after a failure).
    private let rebuild: () async -> Bool

    init(tick: @escaping () async -> Void, tickIsDue: @escaping () -> Bool, rebuild: @escaping () async -> Bool) {
        self.tick = tick
        self.tickIsDue = tickIsDue
        self.rebuild = rebuild
    }

    /// Asks for a tick.
    func requestTick() {
        tickRequested = true
        startIfIdle()
    }

    /// Lets the queue run a tick that has come due.
    func wake() {
        startIfIdle()
    }

    /// Queues a step, unless one with its key waits; a stopping queue
    /// cancels it at once.
    func enqueue(_ key: String, cancel: (() -> Void)? = nil, run: @escaping () async -> Void) {
        guard !isStopping else {
            cancel?()
            return
        }
        if !steps.contains(where: { $0.key == key }) {
            steps.append(Step(key: key, run: run, cancel: cancel))
        }
        startIfIdle()
    }

    /// Runs whatever is due until nothing is: ticks first, then queued
    /// steps, then rebuild passes. Called while the queue runs, it returns
    /// when that run ends.
    func drain() async {
        guard !running else {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        running = true
        while !isStopping {
            if tickRequested || tickIsDue() {
                tickRequested = false
                await tick()
            } else if !steps.isEmpty {
                await steps.removeFirst().run()
            } else if await !rebuild(), !tickRequested, steps.isEmpty {
                break
            }
            await Task.yield()
        }
        running = false
        let finished = waiters
        waiters = []
        for waiter in finished {
            waiter.resume()
        }
    }

    /// SIGTERM: cancels the waiting steps and returns once the running one is done.
    func stop() async {
        isStopping = true
        let cancelled = steps
        steps = []
        for step in cancelled {
            step.cancel?()
        }
        if running {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func startIfIdle() {
        if !running {
            Task { await drain() }
        }
    }
}
