import SwiftUI
import SwiftData

/// Bookmarked verses (SwiftData). Verbatim text; tap to open the composition; swipe to delete.
struct SavedScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedLine.savedAt, order: .reverse) private var saved: [SavedLine]

    var body: some View {
        Group {
            if saved.isEmpty {
                ContentUnavailableView("No saved verses", systemImage: "bookmark",
                                       description: Text("Press and hold any verse, then Save."))
            } else {
                List {
                    ForEach(saved) { item in
                        LineRow(gurmukhi: item.gurmukhi, translit: item.translit,
                                meta: "Ang \(String(item.ang))",
                                lineId: item.lineId, ang: item.ang, compId: item.compId) {
                            container.present(.shabad(compId: item.compId, focusLineId: item.lineId))
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Ink.base)
                    }
                    .onDelete { idx in
                        let removed = idx.map { (saved[$0].lineId, saved[$0].compId) }
                        for i in idx { modelContext.delete(saved[i]) }
                        do {
                            try modelContext.save()
                            // only once the delete is kept: a failed save restores the row, and
                            // its search entry must still be there with it
                            for (lineId, compId) in removed { SpotlightIndex.remove(lineId: lineId, compId: compId) }
                        } catch { modelContext.rollback() }
                    }
                }
                .listStyle(.plain)
                .inkPlainList()
            }
        }
        .background(Ink.base.ignoresSafeArea())
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
    }
}
