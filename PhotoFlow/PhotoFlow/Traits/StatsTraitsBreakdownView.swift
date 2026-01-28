import SwiftUI

struct TraitBreakdownRow: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let percentText: String
    let isActive: Bool
}

struct StatsTraitsBreakdownView: View {
    let groups: [String]
    @Binding var selectedGroup: String
    let rows: [TraitBreakdownRow]
    let totalSessions: Int
    let taggedSessions: Int
    let untaggedSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("客户群体占比")
                .font(.headline)
            if groups.isEmpty {
                Text("暂无特征")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("分组")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("分组", selection: $selectedGroup) {
                        ForEach(groups, id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                    .pickerStyle(.menu)
                }
                let coverageText = totalSessions > 0
                    ? "\(Int((Double(taggedSessions) / Double(totalSessions) * 100).rounded()))%"
                    : "--"
                Text("已标注 \(taggedSessions)/\(totalSessions) · 覆盖率 \(coverageText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if rows.isEmpty {
                    Text("暂无特征")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .foregroundStyle(row.isActive ? .primary : .secondary)
                            Spacer()
                            Text("\(row.count)")
                                .monospacedDigit()
                            Text(row.percentText)
                                .monospacedDigit()
                        }
                        .font(.footnote)
                    }
                }
                if untaggedSessions > 0 {
                    Text("未标注 \(untaggedSessions)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
