// The engine callbacks of SyncCoordinator: batches, send results, fetched
// changes, state, and account changes (data_and_sync.md §3.1).

public import Foundation
import os

extension SyncCoordinator {
    /// The record behind a pending change the engine names only by record
    /// name; `nil` for a name the store never had.
    public func pendingRef(named name: String) async -> SyncRecordRef? {
        if let flight = inFlight[name] {
            return flight.ref
        }
        return try? await store.recordRef(named: name)
    }

    /// The next batch from the engine's pending changes. A pending
    /// `LiveState` travels with the pending entries, atomically.
    public func nextBatch(_ pending: [SyncPendingChange]) async -> SyncBatch? {
        do {
            let changes = Array(Self.ordered(pending).prefix(Self.batchLimit))
            let saved = changes.compactMap { change -> SyncRecordRef? in
                if case let .save(ref) = change {
                    return ref
                }
                return nil
            }
            let (sequence, records) = try await store.syncSnapshot(saved)
            var batch = SyncBatch(records: [], deletions: [], atomic: false, dropped: [])
            for change in changes {
                switch change {
                case let .save(ref):
                    guard let record = records[ref] else {
                        batch.dropped.append(change)
                        continue
                    }
                    batch.records.append(record)
                case let .delete(ref):
                    batch.deletions.append(ref)
                }
                inFlight[change.ref.name] = (change.ref, sequence)
            }
            batch.atomic = batch.records.contains { $0.ref.type == .liveState }
            return batch.isEmpty && batch.dropped.isEmpty ? nil : batch
        } catch {
            Self.logger.error("Building a batch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `LiveState` and the time entries first when they fit one batch;
    /// otherwise `LiveState` last.
    static func ordered(_ pending: [SyncPendingChange]) -> [SyncPendingChange] {
        let live = pending.filter { $0.ref.type == .liveState }
        guard !live.isEmpty else {
            return pending
        }
        let entries = pending.filter { $0.ref.type == .timeEntry }
        let rest = pending.filter { $0.ref.type != .liveState && $0.ref.type != .timeEntry }
        if entries.count + live.count <= batchLimit {
            return live + entries + rest
        }
        return entries + rest + live
    }

    /// What the server answered: confirms the outbox rows, merges conflicts,
    /// re-saves unknown items without system fields, recreates a missing
    /// zone; transient failures stay pending in the engine.
    public func didSend(_ outcome: SyncSendOutcome) async {
        do {
            let failures = try await resolve(outcome.failures)
            var through: [SyncRecordRef: Int64] = [:]
            for name in outcome.saved.map(\.ref.name) + outcome.deletedNames + failures.settled {
                if let flight = inFlight.removeValue(forKey: name) {
                    through[flight.ref] = flight.sequence
                }
            }
            let event = try await store.confirmSent(through, saved: outcome.saved)
            if failures.zoneMissing {
                Self.logger.notice("The zone is missing; recreating it and sending every record")
                await engine?.addZone()
                try await store.requeueAll()
            }
            if !failures.forget.isEmpty {
                await engine?.removePending(failures.forget)
            }
            _ = await drain()
            if let event {
                await liveStateHandler?(event)
            }
        } catch {
            report(error)
        }
    }

    /// Merges conflicts and re-queues unknown items; returns the names whose
    /// outbox rows are settled, the pending changes the engine drops, and
    /// whether the zone is missing.
    private func resolve(_ failures: [SyncSaveResult]) async throws -> ResolvedFailures {
        var resolved = ResolvedFailures()
        for failure in failures {
            switch failure {
            case let .conflict(server):
                try await store.resolveConflict(server: server)
                resolved.settled.append(server.ref.name)
                resolved.forget.append(.save(server.ref))
            case let .unknownItem(ref):
                try await store.requeueWithoutSystemFields([ref])
                resolved.settled.append(ref.name)
                resolved.forget.append(.save(ref))
            case let .zoneNotFound(ref):
                resolved.zoneMissing = true
                resolved.forget.append(.save(ref))
            case .retry, .saved, .deleted:
                break
            }
        }
        return resolved
    }

    /// Applies fetched records in one transaction with the invariant pass.
    public func didFetch(_ records: [SyncRecord], deletions: [SyncRecordRef]) async {
        guard !records.isEmpty || !deletions.isEmpty else {
            return
        }
        do {
            let event = try await store.applyFetched(records, deletions: deletions)
            if let event {
                await liveStateHandler?(event)
            }
            await appliedHandler?()
        } catch {
            report(error)
        }
    }

    /// The zone was deleted on the server: recreate it and send everything.
    public func zoneDeleted() async {
        Self.logger.notice("The zone was deleted on the server; recreating it")
        do {
            await engine?.addZone()
            try await store.requeueAll()
            _ = await drain()
        } catch {
            report(error)
        }
    }

    /// Saves the engine's serialized state.
    public func stateChanged(_ data: Data) async {
        do {
            try await store.setSyncState(Self.engineStateKey, data)
        } catch {
            report(error)
        }
    }

    /// An account change (§3.1 item 5): without an account the store works
    /// locally; another account empties the store after confirmation, or
    /// stops sync when declined.
    public func accountChanged(_ change: SyncAccountChange) async {
        switch change {
        case .signIn:
            setStatus(.idle)
            await engine?.addZone()
            _ = await drain()
        case .signOut:
            setStatus(.noAccount)
        case .switchAccounts:
            guard await confirmSwitch() else {
                Self.logger.notice("Account switch declined; sync stopped")
                stop()
                setStatus(.error("Signed in to a different iCloud account."))
                return
            }
            do {
                try await store.resetForAccountSwitch()
                inFlight = [:]
                await engine?.addZone()
                setStatus(.idle)
            } catch {
                report(error)
            }
        }
    }

    /// The engine's own progress.
    public func engineStatus(_ status: SyncStatus) {
        setStatus(status)
    }
}

/// The follow-ups of a batch's per-record failures.
struct ResolvedFailures {
    var settled: [String] = []
    var forget: [SyncPendingChange] = []
    var zoneMissing = false
}
