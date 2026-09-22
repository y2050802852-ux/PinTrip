import CoreLocation
import SwiftUI

struct DropPinSheet: View {
    let coordinate: CLLocationCoordinate2D?
    let onCommit: (String, PlaceCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: PlaceCategory = .sight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加标注")
                .font(.headline)

            if let coordinate {
                Text(String(
                    format: "%.5f, %.5f",
                    coordinate.latitude,
                    coordinate.longitude
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TextField("地点名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)

            Picker("分类", selection: $category) {
                ForEach(PlaceCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func commit() {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed, category)
        dismiss()
    }
}
