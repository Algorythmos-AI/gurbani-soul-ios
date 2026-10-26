import Foundation

/// The printed saroop's Ang count — the ONE place the number is written. The corpus pipeline's
/// golden gate proves the database covers exactly these Angs (1…count, gap-free), and
/// `GranthAngsTests` checks the bundled database against it, so every bound, clamp and label that
/// needs the count before the database's metadata has loaded reads it here instead of typing it.
/// Surfaces that already hold the metadata derive it from the data (`GranthMap.angCount`).
public enum GranthAngs {
    public static let count = 1430
    public static var all: ClosedRange<Int> { 1...count }
}
