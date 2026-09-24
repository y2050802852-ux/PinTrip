import SwiftData
import SwiftUI

/// Renames a place in place. Attached to the list row's context menu.
struct RenameSheet: View {
    @Bindable var place: Place
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名地点")
                .font(.headline)
            TextField("地点名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { name = place.name }
    }

    private func commit() {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        place.name = trimmed
        try? context.save()
        dismiss()
    }
}
