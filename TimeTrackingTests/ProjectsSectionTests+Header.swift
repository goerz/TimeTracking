// The projects table's column headers and the stored sort
// (spec_projects.md §2.2).

import Foundation
import SwiftUI
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension ProjectsSectionTests {
    @Test("PP-5 a header click sorts by its column ascending, a second click reverses; the header shows the stored sort")
    func headerSort() async throws {
        let test = try await TestApp()
        let model = test.app.sections.projects
        let order = ProjectTableItem.sortOrder(Binding { model.options } set: { model.options = $0 })
        #expect(order.wrappedValue.first?.order == .forward)
        #expect(order.wrappedValue.first.map { $0.keyPath as AnyKeyPath } == ProjectTableItem.sortPath(.name) as AnyKeyPath)
        order.wrappedValue = [KeyPathComparator(ProjectTableItem.sortPath(.totalTracked), order: .reverse)]
        #expect(model.options.sort == .totalTracked)
        #expect(model.options.ascending)
        order.wrappedValue = [KeyPathComparator(ProjectTableItem.sortPath(.totalTracked), order: .reverse)]
        #expect(!model.options.ascending)
        #expect(order.wrappedValue.first?.order == .reverse)
    }
}
