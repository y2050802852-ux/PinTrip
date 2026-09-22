import SwiftUI

/// Card shown while a place is previewed on the map but not yet added.
struct PreviewCard: View {
    let preview: PlacePreview
    let dayOptions: [Int]
    let dateForDay: (Int) -> Date?
    let selectedDay: Int
    let onSelectDay: (Int) -> Void
    /// Receives the (possibly user-edited) name and chosen category.
    let onAdd: (String, PlaceCategory) -> Void
    let onCancel: () -> Void

    @State private var draftName: String
    @State private var category: PlaceCategory = .sight

    init(
        preview: PlacePreview,
        dayOptions: [Int],
        dateForDay: @escaping (Int) -> Date?,
        selectedDay: Int,
        onSelectDay: @escaping (Int) -> Void,
        onAdd: @escaping (String, PlaceCategory) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.preview = preview
        self.dayOptions = dayOptions
        self.dateForDay = dateForDay
        self.selectedDay = selectedDay
        self.onSelectDay = onSelectDay
        self.onAdd = onAdd
        self.onCancel = onCancel
        _draftName = State(initialValue: preview.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.orange)
                Text(preview.source == .search ? "待添加" : "新标注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            if preview.needsName {
                TextField("地点名称", text: $draftName)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(preview.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !preview.subtitle.isEmpty {
                    Text(preview.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                Text("添加到")
                    .font(.callout)
                Picker("", selection: Binding(
                    get: { selectedDay },
                    set: onSelectDay
                )) {
                    ForEach(dayOptions, id: \.self) { day in
                        if let date = dateForDay(day) {
                            Text("第 \(day) 天 · \(date.formatted(.dateTime.month().day()))")
                                .tag(day)
                        } else {
                            Text("第 \(day) 天").tag(day)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            if preview.needsName {
                Picker("分类", selection: $category) {
                    ForEach(PlaceCategory.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("添加") { onAdd(draftName.trimmed.isEmpty ? preview.name : draftName, category) }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmed.isEmpty && preview.needsName)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}
