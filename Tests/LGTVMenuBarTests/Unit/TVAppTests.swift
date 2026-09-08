import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TVApp Tests")
struct TVAppTests {

    @Test("parses launchPoints entries")
    func parsesLaunchPointsEntries() {
        let payload: [String: Any] = [
            "launchPoints": [
                ["id": "netflix", "title": "Netflix", "launchPointId": "netflix_default"],
                ["appId": "youtube.leanback.v4", "title": "YouTube"],
                ["title": "Missing id"],
            ]
        ]

        let apps = TVApp.parseListLaunchPoints(payload)

        #expect(apps.map(\.id) == ["netflix", "youtube.leanback.v4"])
        #expect(apps[0].title == "Netflix")
        #expect(apps[0].launchPointId == "netflix_default")
        #expect(apps[1].launchPointId == nil)
    }

    @Test("falls back to apps key and id as title")
    func fallsBackToAppsKeyAndIdAsTitle() {
        let payload: [String: Any] = [
            "apps": [["id": "com.webos.app.livetv"]]
        ]

        let apps = TVApp.parseListLaunchPoints(payload)

        #expect(apps.count == 1)
        #expect(apps[0].id == "com.webos.app.livetv")
        #expect(apps[0].title == "com.webos.app.livetv")
    }

    @Test("empty payload yields no apps")
    func emptyPayloadYieldsNoApps() {
        #expect(TVApp.parseListLaunchPoints([:]).isEmpty)
    }
}
