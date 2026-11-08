import XCTest

final class NavigationTests: XCTestCase {
    func testRedesignedScreensWithFixtures() {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "dark", "-language", "tr", "-serverURL", "http://127.0.0.1:8879"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bugünün ritmini bul."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Türkiye’de şimdi"].waitForExistence(timeout: 15))
        shot(app, "Redesign-Home-Dark")
        tapTab("nav.discover", label: "Keşfet", in: app)
        XCTAssertTrue(app.staticTexts["Biraz başka bir şey."].waitForExistence(timeout: 5))
        shot(app, "Redesign-Discover-Dark")
        tapTab("nav.library", label: "Kütüphane", in: app)
        XCTAssertTrue(app.buttons["library.favorites"].waitForExistence(timeout: 5))
        shot(app, "Redesign-Library-Dark")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["Ses kalitesi"].waitForExistence(timeout: 5))
        shot(app, "Redesign-Settings-Dark")
        app.navigationBars["Ayarlar"].buttons["Bitti"].tap()
        tapTab("nav.search", label: "Ara", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Gece Yolu\n")
        let row = app.buttons["track.row.fixture:lyrics"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        shot(app, "Redesign-Search-Dark")
        row.tap()
        XCTAssertTrue(app.buttons["player.open"].waitForExistence(timeout: 10))
        app.buttons["player.open"].tap()
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["player.favorite"].exists)
        XCTAssertTrue(app.buttons["lyrics.toggle"].exists)
        shot(app, "Redesign-Player-Dark")
        app.terminate()
    }

    private func launch(theme: String = "light", offline: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", theme, "-language", "tr"]
        if offline { app.launchArguments += ["-serverURL", "http://127.0.0.1:1"] }
        app.launch(); return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let text = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
        for brand in ["youtube", "apple music", "spotify", "jiosaavn"] { XCTAssertFalse(text.contains(brand), "Visible service name: \(brand)") }
    }
    @discardableResult
    private func tapTab(_ identifier: String, label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "The system tab bar must be visible", file: file, line: line)
        // SwiftUI can expose the identifier on either the UITabBar button or its label.
        let candidates = [bar.buttons[identifier], bar.buttons[label], bar.buttons.containing(.any, identifier: identifier).firstMatch]
        // iOS 26 collapses the other tabs into the previous-tab button while search is open.
        // Expand that native control before asking for another tab.
        if !candidates.contains(where: { $0.exists }), app.searchFields.firstMatch.exists, bar.buttons.count == 1 {
            bar.buttons.firstMatch.tap()
        }
        let button = candidates.first(where: { $0.exists }) ?? bar.buttons[identifier]
        XCTAssertTrue(button.exists, "Missing native tab: \(label)", file: file, line: line)
        XCTAssertTrue(button.isHittable, "Native tab is obscured: \(label)", file: file, line: line)
        if button.exists && button.isHittable { button.tap() }
        return button
    }
    func testLyricsFollowAndLineSeeking() {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "dark", "-language", "tr", "-serverURL", "http://127.0.0.1:8879"]
        app.launch()
        tapTab("nav.search", label: "Ara", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Gece Yolu\n")
        let row = app.buttons["track.row.fixture:lyrics"]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.buttons["player.open"].waitForExistence(timeout: 15))
        app.buttons["player.open"].tap()
        XCTAssertTrue(app.buttons["lyrics.toggle"].waitForExistence(timeout: 10))
        let playing = NSPredicate(format: "value == 'playing'")
        expectation(for: playing, evaluatedWith: app.buttons["player.playPause"])
        waitForExpectations(timeout: 15)
        app.buttons["player.playPause"].tap()
        let paused = NSPredicate(format: "value == 'paused'")
        expectation(for: paused, evaluatedWith: app.buttons["player.playPause"])
        waitForExpectations(timeout: 5)
        shot(app, "10-Player-Dark")
        app.buttons["lyrics.toggle"].tap()
        let first = app.buttons["lyrics.line.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        // SwiftUI exposes the unchanged LyricsView's outer identifier on its scroll view.
        let specificScroll = app.scrollViews["lyrics.scroll"]
        let lyricsScroll = specificScroll.exists ? specificScroll : app.scrollViews["lyrics.content"]
        XCTAssertTrue(lyricsScroll.waitForExistence(timeout: 5)); lyricsScroll.swipeUp()
        // The outer identifier can also propagate over the overlay button on iOS 26.
        let namedFollow = app.buttons["lyrics.follow"]
        let follow = namedFollow.exists ? namedFollow : app.buttons.matching(NSPredicate(format: "label == %@", "Sözleri takip et")).firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        follow.tap()
        XCTAssertFalse(follow.exists)
        let nextLine = app.buttons["lyrics.line.3"]
        for _ in 0..<3 { if nextLine.isHittable { break }; lyricsScroll.swipeUp() }
        XCTAssertTrue(nextLine.isHittable); nextLine.tap()
        let seeked = NSPredicate { _, _ in
            let value = Int(app.staticTexts["player.elapsed"].value as? String ?? "0") ?? 0
            return (16...17).contains(value)
        }
        expectation(for: seeked, evaluatedWith: app); waitForExpectations(timeout: 10)
        shot(app, "11-Lyrics-Dark")
        app.buttons["lyrics.toggle"].tap()
        XCTAssertEqual(app.buttons["lyrics.toggle"].value as? String, "hidden")
        app.buttons["player.queue"].tap()
        XCTAssertTrue(app.navigationBars["Çalma sırası"].waitForExistence(timeout: 5))
        app.navigationBars["Çalma sırası"].buttons["Kapat"].tap()
        app.buttons["player.close"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }
    func testNativeTabBarNavigationOffline() {
        XCUIDevice.shared.orientation = .portrait
        for theme in ["light", "dark"] {
            let app = launch(theme: theme, offline: true)
            let home = tapTab("nav.home", label: "Dinle", in: app)
            XCTAssertTrue(home.isSelected)
            XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 10))
            shot(app, "Native-Tabs-Home-\(theme)")

            let discover = tapTab("nav.discover", label: "Keşfet", in: app)
            XCTAssertTrue(discover.isSelected)
            XCTAssertTrue(app.navigationBars["Keşfet"].exists)
            shot(app, "Native-Tabs-Discover-\(theme)")

            tapTab("nav.library", label: "Kütüphane", in: app)
            XCTAssertTrue(app.navigationBars["Kütüphane"].waitForExistence(timeout: 5))
            app.buttons["library.favorites"].tap()
            XCTAssertTrue(app.navigationBars["Favoriler"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should remain visible in a library detail")
            app.navigationBars["Favoriler"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Kütüphane"].waitForExistence(timeout: 5))
            shot(app, "Native-Tabs-Library-\(theme)")

            tapTab("nav.search", label: "Ara", in: app)
            // Selecting the native search role replaces its tab button with the search field.
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
            shot(app, "Native-Tabs-Search-\(theme)")

            tapTab("nav.home", label: "Dinle", in: app)
            app.buttons["settings.open"].tap()
            XCTAssertTrue(app.staticTexts["Ses kalitesi"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.textFields["settings.server"].exists)
            app.navigationBars["Ayarlar"].buttons["Bitti"].tap()
            XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
            XCTAssertTrue(tapTab("nav.library", label: "Kütüphane", in: app).isSelected)
            app.terminate()
        }
    }
    func testCreatePlaylistAndOpenSettings() {
        let app = launch()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Türkiye’de şimdi"].waitForExistence(timeout: 45))
        shot(app, "01-Home-Light")
        tapTab("nav.discover", label: "Keşfet", in: app); shot(app, "02-Discover")
        tapTab("nav.library", label: "Kütüphane", in: app)
        for _ in 0..<3 {
            if app.buttons["playlist.create"].exists && app.buttons["playlist.create"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["playlist.create"].tap()
        let name = "Gece Yolculuğu \(Int(Date().timeIntervalSince1970))"
        app.alerts.textFields.firstMatch.tap(); app.alerts.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Oluştur"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        app.staticTexts[name].tap()
        XCTAssertTrue(app.staticTexts["İlk şarkını ekle"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        shot(app, "03-Library")
        tapTab("nav.home", label: "Dinle", in: app)
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["Ses kalitesi"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.textFields["settings.server"].exists)
        XCTAssertTrue(app.staticTexts["KlyMusic"].exists)
        shot(app, "04-Settings")
        app.terminate()
        let dark = launch(theme: "dark")
        XCTAssertTrue(dark.staticTexts["Türkiye’de şimdi"].waitForExistence(timeout: 45))
        shot(dark, "05-Home-Dark")
    }
    func testLiveTurkishPlaybackDownloadAndOffline() throws {
        let app = launch()
        tapTab("nav.search", label: "Ara", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("BLOK3 VUR\n")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "track.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 45))
        let identifier = row.identifier
        row.tap()
        XCTAssertTrue(app.buttons["player.open"].waitForExistence(timeout: 60))
        app.buttons["player.open"].tap()
        XCTAssertTrue(app.buttons["lyrics.toggle"].waitForExistence(timeout: 10))
        let playing = NSPredicate(format: "value == 'playing'")
        expectation(for: playing, evaluatedWith: app.buttons["player.playPause"])
        waitForExpectations(timeout: 90)
        let advances = NSPredicate { _, _ in (Int(app.staticTexts["player.elapsed"].value as? String ?? "0") ?? 0) >= 3 }
        expectation(for: advances, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["VUR"].exists)
        shot(app, "06-BLOK3-Playing")
        app.buttons["player.favorite"].tap()
        if app.buttons["player.download"].isEnabled { app.buttons["player.download"].tap() }
        app.buttons["player.close"].tap()
        shot(app, "07-Search")
        tapTab("nav.library", label: "Kütüphane", in: app)
        app.buttons["library.downloads"].tap()
        let downloaded = app.buttons[identifier]
        XCTAssertTrue(downloaded.waitForExistence(timeout: 180))
        shot(app, "08-Downloads")
        app.terminate()
        let offline = launch(offline: true)
        tapTab("nav.library", label: "Kütüphane", in: offline)
        offline.buttons["library.downloads"].tap()
        let local = offline.buttons[identifier]
        XCTAssertTrue(local.waitForExistence(timeout: 10)); local.tap()
        XCTAssertTrue(offline.buttons["player.open"].waitForExistence(timeout: 10)); offline.buttons["player.open"].tap()
        expectation(for: playing, evaluatedWith: offline.buttons["player.playPause"])
        waitForExpectations(timeout: 20)
        XCTAssertTrue(offline.staticTexts["Çevrimdışı"].exists)
        let offlineAdvances = NSPredicate { _, _ in (Int(offline.staticTexts["player.elapsed"].value as? String ?? "0") ?? 0) >= 3 }
        expectation(for: offlineAdvances, evaluatedWith: offline)
        waitForExpectations(timeout: 15)
        shot(offline, "09-BLOK3-Offline")
    }

    func testBlackDesignFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "dark", "-language", "tr", "-serverURL", "http://127.0.0.1:8879"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Türkiye’de şimdi"].waitForExistence(timeout: 20))
        shot(app, "20-Black-Home")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.buttons["settings.quality"].waitForExistence(timeout: 5))
        shot(app, "21-Black-Settings")
        app.buttons["settings.quality"].tap()
        let high = app.buttons["Yüksek kalite"]
        XCTAssertTrue(high.waitForExistence(timeout: 5)); high.tap()
        XCTAssertEqual(app.buttons["settings.quality"].value as? String, "Yüksek kalite")
        app.buttons["settings.quality"].tap()
        app.buttons["Otomatik"].tap()
        app.navigationBars["Ayarlar"].buttons["Bitti"].tap()
        tapTab("nav.discover", label: "Keşfet", in: app)
        shot(app, "22-Black-Discover")
        tapTab("nav.library", label: "Kütüphane", in: app)
        shot(app, "23-Black-Library")
        tapTab("nav.search", label: "Ara", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Gece Yolu\n")
        let row = app.buttons["track.row.fixture:lyrics"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.buttons["player.open"].waitForExistence(timeout: 10))
        app.buttons["player.open"].tap()
        let play = app.buttons["player.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == 'playing'"), evaluatedWith: play)
        waitForExpectations(timeout: 15)
        play.tap()
        shot(app, "24-Black-Player")
        app.buttons["lyrics.toggle"].tap()
        XCTAssertTrue(app.buttons["lyrics.line.0"].waitForExistence(timeout: 10))
        shot(app, "25-Preserved-Lyrics")
        app.buttons["lyrics.toggle"].tap()
        app.buttons["player.queue"].tap()
        XCTAssertTrue(app.navigationBars["Çalma sırası"].waitForExistence(timeout: 5))
        shot(app, "26-Black-Queue")
        app.terminate()
    }
}
