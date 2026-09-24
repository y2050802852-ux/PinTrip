import SwiftData
import SwiftUI

struct UndoBanner: View {
    let controller: UndoController
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.secondary)
            Text(controller.message)
                .font(.callout)
            Spacer()
            Button("撤销") {
                guard let deletion = controller.pending else { return }
                let store = PlanStore(context: context)
                _ = store.restore(deletion)
                controller.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
        .padding(.horizontal, 24)
    }
}
