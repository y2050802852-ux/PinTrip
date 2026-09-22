import SwiftData
import SwiftUI

/// Inspector for the selected place: category, day, rating, visited,
/// notes and link. Editing happens in place on the SwiftData object and is
/// saved back through the shared model context.
struct PlaceDetailView: View {
    let place: Place
    let onRemove: () -> Void
    /// Called after the duplicate is created; the caller selects it.
    let onDuplicate: (Place) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("基本信息") {
                LabeledContent("名称") {
                    Text(place.name)
                        .multilineTextAlignment(.trailing)
                }
                Picker("分类", selection: Binding(
                    get: { place.category },
                    set: { place.category = $0; save() }
                )) {
                    ForEach(PlaceCategory.allCases) { category in
                        HStack {
                            Image(systemName: category.symbolName)
                                .foregroundStyle(category.tint)
                            Text(category.rawValue)
                        }
                        .tag(category)
                    }
                }
                Stepper(value: Binding(
                    get: { place.day },
                    set: { place.day = max(1, $0); save() }
                ), in: 1...99) {
                    Text("第 \(place.day) 天")
                }
            }

            Section("评价") {
                RatingPicker(rating: Binding(
                    get: { place.rating },
                    set: { place.rating = $0; save() }
                ))
                Toggle("已去过", isOn: Binding(
                    get: { place.visited },
                    set: { place.visited = $0; save() }
                ))
            }

            Section("备注") {
                TextEditor(text: Binding(
                    get: { place.notes },
                    set: { place.notes = $0; save() }
                ))
                .frame(minHeight: 80)
                .font(.body)
            }

            Section("链接") {
                TextField("https://…", text: Binding(
                    get: { place.linkURL },
                    set: { place.linkURL = $0; save() }
                ))
                .textFieldStyle(.roundedBorder)

                if let url = place.link, let nsURL = URL(string: url) {
                    Link("打开链接", destination: nsURL)
                        .font(.callout)
                }
            }

            Section {
                Button {
                    onDuplicate(duplicateInPlace())
                } label: {
                    Label("复制地点", systemImage: "doc.on.doc")
                }
                Button("从本计划移除", role: .destructive, action: onRemove)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
    }

    /// Duplicates this place in its first plan (the one being viewed).
    private func duplicateInPlace() -> Place {
        let plan = place.plans.first!
        return PlanStore(context: context).duplicate(place, in: plan)
    }

    private func save() {
        try? context.save()
    }
}

private struct RatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("评分")
            Spacer()
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
