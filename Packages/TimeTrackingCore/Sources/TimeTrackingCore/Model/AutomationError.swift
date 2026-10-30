// AutomationError: the failures of the scripting surfaces and their exit
// codes (spec_automation.md §3.11, §5).

import Foundation

/// Why a tool command, intent, or URL action failed. The message is the
/// one line the tool prints after `error:`; intents throw the same text.
public enum AutomationError: Error, Equatable, Sendable, LocalizedError {
    /// Exit 1: I/O and everything else.
    case failure(String)
    /// Exit 2: unknown option, malformed date or color, range too large,
    /// missing `--yes`, conflicting options.
    case usage(String)
    /// Exit 3: a named project, area, client, or entry was not found.
    case notFound(String)
    /// Exit 3: a name matched several records; `candidates` names them.
    case ambiguous(String, candidates: [String])
    /// Exit 4: refused by a store rule.
    case refused(String)
    /// Exit 5: the store is missing, locked, or newer.
    case storeUnavailable(String)
    /// Exit 6: `check` found inconsistencies (the lines are the output).
    case inconsistent
    /// Exit 7: an input file failed to parse or validate.
    case invalidInput(String)

    /// The process exit code of section 3.11.
    public var exitCode: Int32 {
        switch self {
        case .failure: 1
        case .usage: 2
        case .notFound, .ambiguous: 3
        case .refused: 4
        case .storeUnavailable: 5
        case .inconsistent: 6
        case .invalidInput: 7
        }
    }

    /// The one-line message.
    public var message: String {
        switch self {
        case let .failure(message), let .usage(message), let .notFound(message), let .refused(message),
             let .storeUnavailable(message), let .invalidInput(message):
            message
        case let .ambiguous(message, candidates):
            candidates.isEmpty ? message : message + " " + candidates.joined(separator: ", ")
        case .inconsistent:
            "Your time data does not match the description."
        }
    }

    /// The candidates of an ambiguous name.
    public var candidates: [String] {
        if case let .ambiguous(_, candidates) = self {
            return candidates
        }
        return []
    }

    public var errorDescription: String? {
        message
    }

    /// The automation error for a store error, with the tool's messages.
    public init(_ error: StoreError) { // swiftlint:disable:this cyclomatic_complexity
        switch error {
        case .emptyName:
            self = .usage("A name must not be empty.")
        case .duplicateName:
            self = .refused("That name is already taken.")
        case .projectArchived:
            self = .refused("The project is archived; unarchive it first.")
        case .areaRetired:
            self = .refused("The area is retired.")
        case .generalArea:
            self = .refused("The general area of a client cannot be renamed.")
        case .activeProjects:
            self = .refused("The area has active projects.")
        case .invalidColor:
            self = .usage("A color must have the form #RRGGBB.")
        case .endBeforeStart:
            self = .refused("The end lies before the start.")
        case .inFuture:
            self = .refused("The time lies in the future.")
        case .referenced:
            self = .refused("It is still in use and can't be deleted.")
        case .unknownID:
            self = .notFound("That project or entry no longer exists.")
        case .retentionExpired:
            self = .refused("It was deleted too long ago to restore.")
        case let .invalidDocument(path, reason):
            self = .invalidInput("\(path): \(reason)")
        case let .newerSchema(version):
            self = .storeUnavailable(
                "Your time data was saved by a newer version (data version \(version); "
                    + "this version reads version \(TimeStore.schemaVersion)). Update the app."
            )
        case .readOnly:
            self = .failure("Your time data can't be changed here.")
        case .busy:
            self = .storeUnavailable("Your time data is busy in another app. Try again.")
        case let .database(message):
            self = .storeUnavailable("Your time data couldn't be opened: \(message)")
        }
    }

    /// Wraps any error: automation and store errors keep their meaning.
    public init(wrapping error: any Error) {
        if let error = error as? Self {
            self = error
        } else if let error = error as? StoreError {
            self.init(error)
        } else {
            self = .failure(error.localizedDescription)
        }
    }

    /// Runs `body`, turning its errors into automation errors.
    static func catching<R>(_ body: () throws -> R) throws(Self) -> R {
        do {
            return try body()
        } catch {
            throw Self(wrapping: error)
        }
    }

    /// Runs `body`, turning its errors into automation errors.
    static func catching<R>(_ body: () async throws -> R) async throws(Self) -> R {
        do {
            return try await body()
        } catch {
            throw Self(wrapping: error)
        }
    }
}
