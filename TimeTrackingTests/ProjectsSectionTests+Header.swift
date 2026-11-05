// The projects table's column headers and the stored sort
// (projects.md §2.2).

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
        let order = ProjectColumnSort.sortOrder(Binding { model.options } set: { model.options = $0 })
        #expect(order.wrappedValue == [ProjectColumnSort(key: .name, order: .forward)])
        order.wrappedValue = [ProjectColumnSort(key: .totalTracked, order: .reverse), ProjectColumnSort(key: .name)]
        #expect(model.options.sort == .totalTracked)
        #expect(model.options.ascending)
        order.wrappedValue = [ProjectColumnSort(key: .totalTracked, order: .reverse)]
        #expect(!model.options.ascending)
        #expect(order.wrappedValue.first?.order == .reverse)
    }

    @Test("PP-5 every sortable header maps to its own sort key, also starting from Name descending")
    func headerSortEveryColumn() async throws {
        let test = try await TestApp()
        let model = test.app.sections.projects
        let order = ProjectColumnSort.sortOrder(Binding { model.options } set: { model.options = $0 })
        order.wrappedValue = [ProjectColumnSort(key: .name, order: .reverse)]
        #expect(model.options.sort == .name)
        #expect(!model.options.ascending)
        for key in ProjectSortKey.allCases where key != .name {
            let previous = order.wrappedValue
            order.wrappedValue = [ProjectColumnSort(key: key)] + previous
            #expect(model.options.sort == key)
            #expect(model.options.ascending)
            #expect(order.wrappedValue == [ProjectColumnSort(key: key, order: .forward)])
        }
    }
}
