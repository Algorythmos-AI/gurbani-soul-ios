import Foundation

/// One English record can cover 2–4 printed lines (dataset 1.4.0+, table `translation_spans`).
/// Parity with serve.py `attach_translations`: every member line present carries the span, and
/// the English sits on the LAST member present in the list, so a list shows it once under the
/// group even when an Ang boundary cuts the span. Pure; the readers call it after their en query.
public enum EnglishSpans {
    public struct Span: Sendable, Equatable {
        public let first: Int
        public let last: Int
        public let en: String
        public init(first: Int, last: Int, en: String) { self.first = first; self.last = last; self.en = en }
    }

    /// `ids` in display order; `en` is the per-line English as stored. Returns the English to
    /// show per id and the span (first...last) of each member id.
    public static func place(ids: [Int], en: [Int: String], spans: [Span])
        -> (en: [Int: String], span: [Int: ClosedRange<Int>]) {
        var outEn = en
        var outSpan: [Int: ClosedRange<Int>] = [:]
        for s in spans {
            let members = ids.filter { $0 >= s.first && $0 <= s.last }
            guard let lastPresent = members.last else { continue }
            for id in members { outSpan[id] = s.first...s.last; outEn[id] = nil }
            outEn[lastPresent] = s.en
        }
        return (outEn, outSpan)
    }
}
