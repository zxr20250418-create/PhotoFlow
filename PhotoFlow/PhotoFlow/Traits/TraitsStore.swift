import Combine
import Foundation
import SwiftUI

struct TraitGroup: Identifiable, Equatable {
    let name: String
    let traits: [TraitDefinition]

    var id: String { name }
}

@MainActor
final class TraitsStore: ObservableObject {
    @Published private(set) var traits: [TraitDefinition] = []

    private let storageKey = "pf_traits_library_v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func trait(for id: String) -> TraitDefinition? {
        traits.first { $0.id == id }
    }

    func groupedTraits(includeInactive: Bool, includeSelectedIds: Set<String> = []) -> [TraitGroup] {
        let filtered = traits.filter { includeInactive || $0.isActive || includeSelectedIds.contains($0.id) }
        let grouped = Dictionary(grouping: filtered) { normalizedGroupName($0.group) }
        let groups = sortedGroupNames(Array(grouped.keys))
        return groups.map { groupName in
            let groupTraits = grouped[groupName] ?? []
            let sorted = sortTraits(groupTraits)
            return TraitGroup(name: groupName, traits: sorted)
        }
    }

    func traits(in group: String, includeInactive: Bool) -> [TraitDefinition] {
        let targetGroup = normalizedGroupName(group)
        let filtered = traits.filter { normalizedGroupName($0.group) == targetGroup && (includeInactive || $0.isActive) }
        return sortTraits(filtered)
    }

    func groupsSorted(includeInactive: Bool) -> [String] {
        let filtered = traits.filter { includeInactive || $0.isActive }
        let groups = Set(filtered.map { normalizedGroupName($0.group) })
        return sortedGroupNames(Array(groups))
    }

    func addTrait(name: String, group: String, isActive: Bool = true) {
        let normalizedGroup = normalizedGroupName(group)
        let nextIndex = nextSortIndex(for: normalizedGroup)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let definition = TraitDefinition(
            name: trimmedName,
            group: normalizedGroup,
            sortIndex: nextIndex,
            isActive: isActive
        )
        traits.append(definition)
        normalizeSortIndices(for: normalizedGroup)
        save()
    }

    func updateTrait(id: String, name: String, group: String, isActive: Bool) {
        guard let index = traits.firstIndex(where: { $0.id == id }) else { return }
        let normalizedGroup = normalizedGroupName(group)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let existing = traits[index]
        var updated = existing
        updated.name = trimmedName
        updated.isActive = isActive
        if normalizedGroup != normalizedGroupName(existing.group) {
            updated.group = normalizedGroup
            updated.sortIndex = nextSortIndex(for: normalizedGroup)
        } else {
            updated.group = normalizedGroup
        }
        traits[index] = updated
        normalizeSortIndices(for: normalizedGroupName(existing.group))
        normalizeSortIndices(for: normalizedGroup)
        save()
    }

    func setActive(_ id: String, isActive: Bool) {
        guard let index = traits.firstIndex(where: { $0.id == id }) else { return }
        traits[index].isActive = isActive
        save()
    }

    func moveTrait(in group: String, from offsets: IndexSet, to destination: Int) {
        let targetGroup = normalizedGroupName(group)
        var groupTraits = traits(in: targetGroup, includeInactive: true)
        guard !groupTraits.isEmpty else { return }
        groupTraits.move(fromOffsets: offsets, toOffset: destination)
        for (index, trait) in groupTraits.enumerated() {
            if let originalIndex = traits.firstIndex(where: { $0.id == trait.id }) {
                traits[originalIndex].sortIndex = index
            }
        }
        save()
    }

    private func nextSortIndex(for group: String) -> Int {
        let targetGroup = normalizedGroupName(group)
        let groupTraits = traits.filter { normalizedGroupName($0.group) == targetGroup }
        let maxIndex = groupTraits.map(\.sortIndex).max() ?? -1
        return maxIndex + 1
    }

    private func normalizeSortIndices(for group: String) {
        let targetGroup = normalizedGroupName(group)
        let sorted = traits
            .filter { normalizedGroupName($0.group) == targetGroup }
            .sorted {
                if $0.sortIndex != $1.sortIndex {
                    return $0.sortIndex < $1.sortIndex
                }
                return $0.name < $1.name
            }
        for (index, trait) in sorted.enumerated() {
            if let originalIndex = traits.firstIndex(where: { $0.id == trait.id }) {
                traits[originalIndex].sortIndex = index
            }
        }
    }

    private func normalizeTraits(_ input: [TraitDefinition]) -> [TraitDefinition] {
        input.map { trait in
            var updated = trait
            updated.group = normalizedGroupName(updated.group)
            return updated
        }
    }

    private func sortTraits(_ input: [TraitDefinition]) -> [TraitDefinition] {
        input.sorted {
            if normalizedGroupName($0.group) != normalizedGroupName($1.group) {
                return normalizedGroupName($0.group) < normalizedGroupName($1.group)
            }
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            return $0.name < $1.name
        }
    }

    private func sortedGroupNames(_ names: [String]) -> [String] {
        let unique = Array(Set(names))
        return unique.sorted { lhs, rhs in
            if lhs == TraitDefinition.defaultGroupName {
                return true
            }
            if rhs == TraitDefinition.defaultGroupName {
                return false
            }
            return lhs < rhs
        }
    }

    private func normalizedGroupName(_ group: String) -> String {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TraitDefinition.defaultGroupName : trimmed
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TraitDefinition].self, from: data) else {
            traits = []
            return
        }
        traits = normalizeTraits(decoded)
        let groups = Set(traits.map { normalizedGroupName($0.group) })
        groups.forEach { normalizeSortIndices(for: $0) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(traits) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
