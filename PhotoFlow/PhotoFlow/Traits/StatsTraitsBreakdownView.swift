import SwiftUI

enum TraitBreakdownMode: String, CaseIterable, Identifiable {
    case sessions = "会话占比"
    case revenue = "收入占比"

    var id: String { rawValue }
}

struct TraitBreakdownRow: Identifiable, Equatable {
    let id: String
    let name: String
    let sessionCount: Int
    let sessionPercentText: String
    let revenueText: String
    let revenuePercentText: String
    let isActive: Bool
}

struct TraitBreakdownSummary: Equatable {
    let totalSessions: Int
    let taggedSessions: Int
    let untaggedSessions: Int
    let amountFilledSessions: Int
    let amountMissingSessions: Int
    let revenueAvailable: Bool
    let untaggedRevenueText: String
    let untaggedRevenuePercentText: String
    let showUntaggedRevenue: Bool
    let rows: [TraitBreakdownRow]
}

struct StatsTraitsBreakdownView: View {
    let groups: [String]
    @Binding var selectedGroup: String
    @Binding var mode: TraitBreakdownMode
    let summary: TraitBreakdownSummary

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
                Picker("占比方式", selection: $mode) {
                    ForEach(TraitBreakdownMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                let coverageText = summary.totalSessions > 0
                    ? "\(Int((Double(summary.taggedSessions) / Double(summary.totalSessions) * 100).rounded()))%"
                    : "--"
                Text("已标注 \(summary.taggedSessions)/\(summary.totalSessions) · 覆盖率 \(coverageText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if mode == .revenue {
                    Text("金额已填：\(summary.amountFilledSessions)/\(summary.totalSessions) 单；未填：\(summary.amountMissingSessions) 单")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if summary.rows.isEmpty {
                    Text("暂无特征")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.rows) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .foregroundStyle(row.isActive ? .primary : .secondary)
                            Spacer()
                            if mode == .sessions {
                                Text("\(row.sessionCount)")
                                    .monospacedDigit()
                                Text(row.sessionPercentText)
                                    .monospacedDigit()
                            } else {
                                Text(row.revenueText)
                                    .monospacedDigit()
                                Text(row.revenuePercentText)
                                    .monospacedDigit()
                                if summary.revenueAvailable {
                                    Text("\(row.sessionCount)单")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.footnote)
                    }
                }
                if mode == .sessions {
                    if summary.untaggedSessions > 0 {
                        Text("未标注 \(summary.untaggedSessions)（\(summary.untaggedSessions)/\(summary.totalSessions)）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if summary.showUntaggedRevenue {
                    Text("未标注收入 \(summary.untaggedRevenueText)（\(summary.untaggedRevenuePercentText)）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
