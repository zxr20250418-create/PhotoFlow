import SwiftUI

struct TraitChipsView: View {
    let groups: [TraitGroup]
    @Binding var selectedIds: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if groups.isEmpty {
                Text("暂无特征")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(group.traits) { trait in
                                let isSelected = selectedIds.contains(trait.id)
                                Button {
                                    toggle(trait.id)
                                } label: {
                                    Text(trait.name)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(chipForeground(isSelected: isSelected, isActive: trait.isActive))
                                        .background(chipBackground(isSelected: isSelected, isActive: trait.isActive))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func chipBackground(isSelected: Bool, isActive: Bool) -> Color {
        if !isActive {
            return Color.secondary.opacity(isSelected ? 0.2 : 0.08)
        }
        return isSelected ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.12)
    }

    private func chipForeground(isSelected: Bool, isActive: Bool) -> Color {
        if !isActive {
            return .secondary
        }
        return isSelected ? .blue : .primary
    }
}
