import SwiftUI
import SwiftData

struct RunLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<CompletedRun>(\.completedAt, order: .reverse)]) private var runs: [CompletedRun]

    var body: some View {
        NavigationView {
            List {
                ForEach(runs, id: \.id) { run in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formattedDate(run.completedAt))
                                .font(RCFont.semiBold(16))
                            Text(summary(run))
                                .font(RCFont.regular(14))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        ShareLink(item: shareMessage(run)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Run Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(runs[index]) }
        try? modelContext.save()
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func summary(_ run: CompletedRun) -> String {
        let duration = run.elapsedSeconds.map { formattedTime($0) } ?? ""
        let miles = run.distanceMeters.map { String(format: "%.2f mi", $0 / 1609.34) } ?? ""
        let parts = [duration, miles].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func shareMessage(_ run: CompletedRun) -> String {
        var parts: [String] = []
        if let t = run.template { parts.append(t) }
        if let s = run.elapsedSeconds { parts.append(formattedTime(s)) }
        if let d = run.distanceMeters { parts.append(String(format: "%.2f mi", d / 1609.34)) }
        let core = parts.isEmpty ? "Run completed" : parts.joined(separator: " · ")
        return "RunClub — \(core)"
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
