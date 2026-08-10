import Foundation

struct HistoryFilters: Equatable {
    var splitName: String?
    var exerciseNameQuery = ""
    var minimumRating: Int?
    var startDate: Date?
    var endDate: Date?

    var isActive: Bool {
        splitName != nil ||
        !exerciseNameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        minimumRating != nil ||
        startDate != nil ||
        endDate != nil
    }
}
