// UserMessage: what the user reads when a change fails, instead of the
// library's error text, which is written for logs (design.md §11).

import Foundation
import os
import TimeTrackingCore

/// User-facing sentences for errors. The library's `errorDescription`s name
/// cases and SQLite messages; views show these instead and log the error.
enum UserMessage {
    /// The message for a failed save, change, or deletion.
    static func text(for error: any Error) -> String {
        guard let error = error as? StoreError else {
            return couldNotSave
        }
        return text(for: error)
    }

    static func text(for error: StoreError) -> String { // swiftlint:disable:this cyclomatic_complexity
        switch error {
        case .emptyName: "Enter a name."
        case .duplicateName: "That name is already used."
        case .projectArchived: "This project is archived. Restore it to use it."
        case .areaRetired: "This area is retired. Reactivate it to use it."
        case .generalArea: "A client's general area can't be renamed."
        case .activeProjects: "This area still has active projects."
        case .invalidColor: "Choose a color from the list."
        case .endBeforeStart: "The end is before the start."
        case .inFuture: "Times can't be in the future."
        case .referenced: "This is still in use."
        case .unknownID: "This was deleted, perhaps on another device."
        case .retentionExpired: "This was deleted too long ago to restore."
        case .invalidDocument: "This file is not a TimeTracking export."
        case .newerSchema: "Your data was saved by a newer version of the app. Update the app on this device."
        case .readOnly, .busy, .database: couldNotSave
        }
    }

    /// Logs `error` under `category` and returns the message for it.
    static func logged(_ error: any Error, category: String) -> String {
        Logging.logger(category: category).error("\(String(describing: error), privacy: .public)")
        return text(for: error)
    }

    /// Any failure without a more specific message.
    static let couldNotSave = "Couldn't save the change. Try again."

    /// The data could not be opened at launch.
    static func openingFailed(_ error: any Error) -> String {
        if case .newerSchema = error as? StoreError {
            return "Your data was saved by a newer version of the app. Update the app on this device."
        }
        return "Quit the app and open it again."
    }
}
