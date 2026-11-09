import SwiftUI

/// The Nitnem home row for the Hukamnama from Sri Harmandir Sahib — beside, never replacing, the
/// Hukam of the day. It shows the Amritsar date and the Ang only: the verse itself is read in the
/// sheet, from the app's own corpus, after its range is proven.
struct HukamnamaCard: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    static let title = "Hukamnama · Sri Harmandir Sahib"

    var body: some View {
        let state = container.hukamnama.cardState()
        Button {
            Haptics.tap()
            container.present(.hukamnama(date: target(state)))
        } label: {
            Card {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "building.columns").font(.title2).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title).font(.headline).foregroundStyle(.primary)
                        Text(Self.subtitle(state)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier("hukamnamaCard")
        .task { await container.hukamnama.refreshIfDue() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await container.hukamnama.refreshIfDue() } }
        }
    }

    private func target(_ state: HukamnamaHome.CardState) -> String? {
        switch state {
        case .published(let e): return e.amritsarDate
        case .notYet(let p), .late(let p): return p?.amritsarDate
        }
    }

    static func subtitle(_ state: HukamnamaHome.CardState, now: Date = Date()) -> String {
        switch state {
        case .published(let e):
            let date = AmritsarDate.label(e.amritsarDate) ?? e.amritsarDate
            return e.ang.map { "\(date) · Ang \(String($0))" } ?? date
        case .notYet:
            return "Not yet published · usually around \(HukamnamaSchedule.usualLocalTime(now: now)) your time"
        case .late:
            return "Delayed today · it will appear here once it has been checked"
        }
    }
}
