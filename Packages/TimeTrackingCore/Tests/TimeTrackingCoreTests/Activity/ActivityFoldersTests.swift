// Tests for ActivityFolders (data_and_sync.md §6, activity_tracking.md §4.1).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityFoldersTests {
    private static let identity = AppIdentity(
        appID: "com.example.timetracking.debug",
        bundleID: "com.example.timetracking",
        teamID: "TEAM000000",
        appGroup: "TEAM000000.com.example.timetracking.debug",
        cloudKitContainer: "iCloud.com.example.timetracking.debug",
        urlScheme: "timetracking-debug"
    )

    @Test func theSharedFolderIsInTheUbiquityContainerOutsideDocuments() {
        let group = URL(filePath: "/tmp/Group", directoryHint: .isDirectory)
        let ubiquity = URL(filePath: "/tmp/Mobile Documents/iCloud~example", directoryHint: .isDirectory)
        let folders = ActivityFolders(identity: Self.identity, groupContainer: group, ubiquityContainer: ubiquity)
        #expect(!folders.isFallback)
        #expect(folders.sharedBlocks.path == "/tmp/Mobile Documents/iCloud~example/Activity/blocks")
        #expect(folders.settingsURL.path == "/tmp/Mobile Documents/iCloud~example/Activity/settings.toml")
        #expect(folders.currentStateURL.path == "/tmp/Group/Library/Application Support/TimeTracking/Activity/current.json")
        #expect(folders.detailFolder.lastPathComponent == "detail")
        #expect(folders.eventsURL.lastPathComponent == "events.jsonl")
        #expect(folders.blockFolders.count == 2)
    }

    @Test func withoutAUbiquityContainerTheLocalFolderIsTheFallback() {
        let group = URL(filePath: "/tmp/Group", directoryHint: .isDirectory)
        let folders = ActivityFolders(identity: Self.identity, groupContainer: group, ubiquityContainer: nil)
        #expect(folders.isFallback)
        #expect(folders.shared == folders.local)
        #expect(folders.settingsURL.path == "/tmp/Group/Library/Application Support/TimeTracking/Activity/settings.toml")
        #expect(folders.blockFolders.count == 1)
    }
}
