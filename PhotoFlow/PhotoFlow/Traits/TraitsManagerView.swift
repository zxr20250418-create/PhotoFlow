import SwiftUI

struct TraitsManagerView: View {
    @ObservedObject var store: TraitsStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingTrait: TraitDefinition?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                let groups = store.groupsSorted(includeInactive: true)
                if groups.isEmpty {
                    Text("暂无特征")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups, id: \.self) { group in
                        Section(group) {
                            let traits = store.traits(in: group, includeInactive: true)
                            if traits.isEmpty {
                                Text("暂无特征")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(traits) { trait in
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(trait.name)
                                                .font(.body)
                                            if !trait.isActive {
                                                Text("已停用")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Toggle("启用", isOn: activeBinding(for: trait))
                                            .labelsHidden()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingTrait = trait
                                    }
                                }
                                .onMove { offsets, destination in
                                    store.moveTrait(in: group, from: offsets, to: destination)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("标签管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("新增") {
                        isAdding = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isAdding) {
                TraitEditorView(
                    title: "新增特征",
                    initialName: "",
                    initialGroup: TraitDefinition.defaultGroupName,
                    initialActive: true
                ) { name, group, isActive in
                    store.addTrait(name: name, group: group, isActive: isActive)
                }
            }
            .sheet(item: $editingTrait) { trait in
                TraitEditorView(
                    title: "编辑特征",
                    initialName: trait.name,
                    initialGroup: trait.group,
                    initialActive: trait.isActive
                ) { name, group, isActive in
                    store.updateTrait(id: trait.id, name: name, group: group, isActive: isActive)
                }
            }
        }
    }

    private func activeBinding(for trait: TraitDefinition) -> Binding<Bool> {
        Binding(
            get: { trait.isActive },
            set: { store.setActive(trait.id, isActive: $0) }
        )
    }
}

private struct TraitEditorView: View {
    let title: String
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var group: String
    @State private var isActive: Bool

    init(
        title: String,
        initialName: String,
        initialGroup: String,
        initialActive: Bool,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _group = State(initialValue: initialGroup)
        _isActive = State(initialValue: initialActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("特征") {
                    TextField("名称", text: $name)
                    TextField("分组", text: $group)
                }
                Section("状态") {
                    Toggle("启用", isOn: $isActive)
                }
                Section {
                    Text("分组为空时默认使用“\(TraitDefinition.defaultGroupName)”")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, group, isActive)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
