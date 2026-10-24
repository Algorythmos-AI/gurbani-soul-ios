import XCTest
@testable import SGGS

/// The Voices map (gated until G3): geography stays the right way round, and voices come from
/// the roster's `place` field (contributors.json v2) — no place, no pin.
final class VoicesMapTests: XCTestCase {

    func testProjectionKeepsGeographyTheRightWayRound() {
        let size = CGSize(width: 360, height: 340)
        let multan = VoicesMap.project(lon: 71.47, lat: 30.20, in: size)
        let banaras = VoicesMap.project(lon: 82.97, lat: 25.32, in: size)
        let pandharpur = VoicesMap.project(lon: 75.33, lat: 17.68, in: size)
        XCTAssertLessThan(multan.x, banaras.x, "Multan is west of Banaras")
        XCTAssertLessThan(multan.y, pandharpur.y, "north is up")
        for lon in [SouthAsiaLand.lonRange.lowerBound, SouthAsiaLand.lonRange.upperBound] {
            for lat in [SouthAsiaLand.latRange.lowerBound, SouthAsiaLand.latRange.upperBound] {
                let p = VoicesMap.project(lon: lon, lat: lat, in: size)
                XCTAssertTrue((0...size.width).contains(p.x) && (0...size.height).contains(p.y), "corner off the canvas")
            }
        }
        XCTAssertFalse(SouthAsiaLand.polygons.isEmpty)
    }

    func testVoicesComeFromTheRosterPlaceField() {
        let v1 = #"{"contributors":[{"name":"Bhagat Kabir Ji","roman":"Kabir","kind":"bhagat","born":1398,"died":1518,"circa":true,"era":"15th century","region":"Banaras","tradition":"Bhakti","blurb":"…"}]}"#
        XCTAssertEqual(MapVoice.decode(Data(v1.utf8)), [], "a v1 roster has no places: nothing is mapped")
        let v2 = #"{"version":2,"map":{"lon":[66,90],"lat":[8,37]},"contributors":[{"name":"Bhagat Kabir Ji","kind":"bhagat","born":1398,"era":"15th century","place":{"label":"Banaras","x":0.7,"y":0.4,"lat":25.32,"lon":82.97,"approx":true}},{"name":"Bhagat Sain Ji","kind":"bhagat","born":null,"era":"uncertain"},{"name":"Bad","kind":"bhagat","place":{"label":"x","lat":"n/a","lon":1}}]}"#
        let v = MapVoice.decode(Data(v2.utf8))
        XCTAssertEqual(v.map(\.name), ["Bhagat Kabir Ji"], "voices without a place (or a malformed one) are not pinned")
        XCTAssertEqual(v.first?.lat, 25.32); XCTAssertEqual(v.first?.label, "Banaras"); XCTAssertEqual(v.first?.year, 1398)
    }

    func testMapIsOffUnlessAReviewerTurnsItOn() {
        UserDefaults.standard.removeObject(forKey: "sggs_voices_map")
        XCTAssertFalse(VoicesFeatures.mapEnabled, "the map waits for the scholar's sign-off (G3)")
    }
}
