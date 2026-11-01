// IdleModel: idle detection and the "You have been away" prompt
// (spec_timer.md §6).

import Foundation
import Observation
import TimeTrackingCore

/// The open prompt.
struct IdlePrompt: Equatable {
    var idleStart: Date
    var entryID: EntryID
    /// "Running: <task> · <project>".
    var runningText: String
}

/// The prompt's options (§6.3).
enum IdleOption: String, CaseIterable, Identifiable {
    case split
    case discardAndContinue
    case discard
    case keep

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .split: "Split"
        case .discardAndContinue: "Discard and Continue"
        case .discard: "Discard"
        case .keep: "Keep"
        }
    }
}

/// Feeds the library's `IdleDetector` and acts on its decisions.
@Observable
final class IdleModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let notifier: NotificationPosting
    @ObservationIgnored let settings: AppSettings
    /// Whether the app is frontmost (the notification is posted otherwise).
    @ObservationIgnored var isAppActive: () -> Bool = { true }
    /// Called after the prompt or a stop changed entries.
    @ObservationIgnored var onChange: (() async -> Void)?
    /// Brings the Mini Timer forward for the prompt; focuses the task field after Split.
    @ObservationIgnored var showTimer: (_ focusTask: Bool) -> Void = { _ in }

    private(set) var prompt: IdlePrompt?
    @ObservationIgnored private var detector: IdleDetector

    init(store: TimeStore, clock: any Clock, notifier: NotificationPosting, settings: AppSettings) {
        self.store = store
        self.clock = clock
        self.notifier = notifier
        self.settings = settings
        self.detector = IdleDetector(settings: settings.idle)
    }

    /// One 10-second sample of the seconds since the last input event.
    func sample(idleSeconds: TimeInterval, presence: TrackerPresence?) async {
        detector.settings = settings.idle
        let running = try? await store.runningEntry()
        let decision = detector.sample(idleSeconds: idleSeconds, at: clock.now, isRunning: running != nil, presence: presence)
        await act(on: decision, running: running)
    }

    /// A lock, sleep, wake, session switch, or shutdown.
    func systemEvent(_ event: IdleSystemEvent, at time: Date) async {
        detector.settings = settings.idle
        let running = try? await store.runningEntry()
        let decision = detector.event(event, at: time, isRunning: running != nil)
        await act(on: decision, running: running)
    }

    /// The running entry changed; a stop elsewhere closes the prompt.
    func runningChanged(_ running: TimeEntry?) {
        guard let prompt, running?.id != prompt.entryID else {
            return
        }
        self.prompt = nil
        notifier.remove([.idle])
    }

    /// Resolves the prompt.
    func resolve(_ option: IdleOption) async {
        guard let prompt else {
            return
        }
        self.prompt = nil
        notifier.remove([.idle])
        detector.reset()
        do {
            guard let running = try await store.runningEntry(), running.id == prompt.entryID else {
                return
            }
            let stopAt = max(prompt.idleStart, running.start)
            switch option {
            case .keep:
                return
            case .discard:
                try await store.stop(at: stopAt)
            case .discardAndContinue:
                try await store.stop(at: stopAt)
                try await store.start(projectID: running.projectID, task: running.task, at: clock.now)
            case .split:
                try await store.start(projectID: nil, task: "", at: stopAt)
                showTimer(true)
            }
            await onChange?()
        } catch {
            return
        }
    }

    private func act(on decision: IdleDecision?, running: TimeEntry?) async {
        switch decision {
        case .none:
            return
        case let .stop(time):
            guard let running else {
                return
            }
            _ = try? await store.stop(at: max(time, running.start))
            await onChange?()
        case let .prompt(idleStart):
            guard let running else {
                return
            }
            await open(idleStart: idleStart, running: running)
        }
    }

    private func open(idleStart: Date, running: TimeEntry) async {
        // A new idle period extends an open prompt.
        let start = min(prompt?.idleStart ?? idleStart, idleStart)
        let listing = try? await store.listings(for: [running]).first
        let project = listing.flatMap { $0.project?.name } ?? "No project"
        let task = running.task.isEmpty ? "No task" : running.task
        prompt = IdlePrompt(idleStart: start, entryID: running.id, runningText: "Running: \(task) · \(project)")
        showTimer(false)
        if !isAppActive() {
            notifier.post(NotificationRequest(
                category: .idle,
                title: "You have been away",
                body: "Idle since \(LocalDateText.time(start)) while tracking \(task).",
                sound: nil
            ))
        }
    }

    /// "Idle since 14:02 (23 minutes)."
    func sinceText(at now: Date) -> String {
        guard let prompt else {
            return ""
        }
        let minutes = Int(now.timeIntervalSince(prompt.idleStart) / 60)
        return "Idle since \(LocalDateText.time(prompt.idleStart)) (\(minutes) minute\(minutes == 1 ? "" : "s"))."
    }
}
