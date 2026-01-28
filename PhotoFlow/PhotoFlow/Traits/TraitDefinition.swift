import Foundation

struct TraitDefinition: Codable, Identifiable, Equatable, Hashable {
    static let defaultGroupName = "客群"

    let id: String
    var name: String
    var group: String
    var sortIndex: Int
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        group: String = TraitDefinition.defaultGroupName,
        sortIndex: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.sortIndex = sortIndex
        self.isActive = isActive
    }
}
