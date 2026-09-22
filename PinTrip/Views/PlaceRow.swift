import SwiftData
import SwiftUI

struct PlaceRow: View {
    let plan: Plan
    let place: Place

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: place.category.symbolName)
                .foregroundStyle(place.category.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body)
                    .strikethrough(place.visited, pattern: .solid)
                    .foregroundStyle(place.visited ? .secondary : .primary)
                metadataLine
            }

            Spacer(minLength: 0)

            Button {
                place.visited.toggle()
                try? context.save()
            } label: {
                Image(systemName: place.visited ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(place.visited ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(place.visited ? "标记为未去过" : "标记为已去过")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("从本计划移除", role: .destructive) {
                PlanStore(context: context).remove(place, from: plan)
            }
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: 6) {
            Text(place.category.rawValue)
            Text("·")
            Text("第 \(place.day) 天")
            if place.rating > 0 {
                Text("·")
                Text(String(repeating: "★", count: place.rating))
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
