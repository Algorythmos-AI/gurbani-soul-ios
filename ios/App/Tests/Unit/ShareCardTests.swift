import XCTest
import SwiftUI
import LinkPresentation
import GurbaniDB
@testable import SGGS

/// The share system (VerseCard.swift): what a shared verse says and links to, and the cards it
/// draws. The verses are not fixtures: they are read from the bundled DB, verbatim. When
/// `SGGS_SHARE_SNAPSHOT_DIR` is set, each card is also written as a PNG for visual review.
@MainActor
final class ShareCardTests: XCTestCase {

    // MARK: text and links

    func testAngLinksAreTheWebSharePages() {
        XCTAssertEqual(ShareLinks.ang(917).absoluteString, "https://gurbanisoul.com/ang/917")
        XCTAssertEqual(ShareLinks.ang(1430, line: 60602).absoluteString, "https://gurbanisoul.com/ang/1430?line=60602")
        XCTAssertEqual(ShareLinks.citation(1430), "Sri Guru Granth Sahib Ji · Ang 1430")   // never "1,430"
    }

    func testVerseTextIsTheLineItsCitationAndItsLink() {
        let g = "ਅਨੰਦੁ ਭਇਆ ਮੇਰੀ ਮਾਏ ਸਤਿਗੁਰੂ ਮੈ ਪਾਇਆ ॥"
        XCTAssertEqual(ShareLinks.verseText(gurmukhi: g, ang: 917, line: 39335),
                       "\(g)\n— Sri Guru Granth Sahib Ji · Ang 917\nhttps://gurbanisoul.com/ang/917?line=39335")
        // a line from another source keeps its own label and carries no Sri Guru Granth Sahib Ji link
        XCTAssertEqual(ShareLinks.verseText(gurmukhi: g, ang: 0, line: nil, sourceLabel: "Ardaas"), "\(g)\n— Ardaas")
        // the line is passed through untouched, scalar for scalar
        let text = ShareLinks.verseText(gurmukhi: g, ang: 917, line: 39335)
        XCTAssertTrue(text.unicodeScalars.starts(with: g.unicodeScalars))
    }

    func testTheCardShareCarriesItsOwnHeader() throws {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let item = ShareCardItem(image: img, title: ShareLinks.citation(14), url: ShareLinks.ang(14, line: 592))
        let m = try XCTUnwrap(item.activityViewControllerLinkMetadata(UIActivityViewController(activityItems: [], applicationActivities: nil)))
        XCTAssertEqual(m.title, "Sri Guru Granth Sahib Ji · Ang 14")
        XCTAssertEqual(m.originalURL?.host(), "gurbanisoul.com")
        XCTAssertNotNil(m.imageProvider)
    }

    func testSharingTheAppSendsTheSite() {
        XCTAssertEqual(AppLinks.website.absoluteString, "https://gurbanisoul.com")
    }

    // MARK: cards

    private func line(_ ang: Int) throws -> (String, String) {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let l = try XCTUnwrap(try SQLiteCandidateSource(path: path).fetchAng(ang).lines.first { !$0.isHeader })
        return (l.gurmukhi, l.translit)
    }

    /// Every verse card is 1080 px wide at 3×, at least square, in both schemes — including the
    /// longest opening line in the Granth's last Angs and a 4-digit citation.
    func testVerseCardsRenderSquareAt1080InBothSchemes() throws {
        for ang in [1, 14, 853, 917, 1430] {
            let (g, t) = try line(ang)
            for scheme in [ColorScheme.light, .dark] {
                for withLayers in [false, true] {
                    let img = try XCTUnwrap(VerseCardRenderer.render(
                        gurmukhi: g, translit: withLayers ? t : "", en: withLayers ? "An English layer." : nil,
                        ang: ang, scheme: scheme), "Ang \(ang) \(scheme)")
                    XCTAssertEqual(img.size.width * img.scale, 1080, accuracy: 0.5, "Ang \(ang)")
                    XCTAssertGreaterThanOrEqual(img.size.height * img.scale, 1080 - 0.5, "Ang \(ang)")
                    snapshot(img, "verse-\(ang)-\(scheme == .dark ? "dark" : "light")\(withLayers ? "-layers" : "")")
                }
            }
        }
    }

    private func snapshot(_ img: UIImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SGGS_SHARE_SNAPSHOT_DIR"], let png = img.pngData() else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
