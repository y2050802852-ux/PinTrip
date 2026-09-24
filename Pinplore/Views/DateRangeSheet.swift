import SwiftUI

/// Date range chosen when creating a plan, or edited later.
struct DateRangeSheet: View {
    enum Mode {
        case create
        case edit
    }

    let mode: Mode
    let initialStart: Date?
    let initialEnd: Date?
    let onCommit: (Date?, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasDates = true
    @State private var start: Date
    @State private var end: Date

    init(
        mode: Mode,
        initialStart: Date?,
        initialEnd: Date?,
        onCommit: @escaping (Date?, Date?) -> Void
    ) {
        self.mode = mode
        self.initialStart = initialStart
        self.initialEnd = initialEnd
        self.onCommit = onCommit

        let calendar = Calendar.current
        let defaultStart = initialStart ?? calendar.startOfDay(for: Date())
        let defaultEnd = initialEnd ?? calendar.date(byAdding: .day, value: 4, to: defaultStart) ?? defaultStart
        _start = State(initialValue: defaultStart)
        _end = State(initialValue: defaultEnd)
        _hasDates = State(initialValue: initialStart != nil)
    }

    private var dayCount: Int {
        guard hasDates else { return 1 }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: end)
        ).day ?? 0
        return max(1, days + 1)
    }

    /// End is not allowed to precede start.
    private var isEndBeforeStart: Bool {
        Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "设置行程日期" : "修改行程日期")
                .font(.headline)

            Toggle("指定日期范围", isOn: $hasDates)
                .help("关闭则作为无日期的单一清单使用")

            if hasDates {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("出发日")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: $start,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .onChange(of: start) { _, newValue in
                            if Calendar.current.startOfDay(for: end)
                                < Calendar.current.startOfDay(for: newValue) {
                                end = newValue
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("返程日")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: $end,
                            in: start...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("共 \(dayCount) 天")
                        .font(.callout)
                    if let formatted = formattedRange {
                        Text("· \(formatted)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)

                if isEndBeforeStart {
                    Text("返程日不能早于出发日")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .create ? "创建" : "保存") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(hasDates && isEndBeforeStart)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var formattedRange: String? {
        guard hasDates else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func commit() {
        if hasDates {
            let calendar = Calendar.current
            onCommit(calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        } else {
            onCommit(nil, nil)
        }
        dismiss()
    }
}
