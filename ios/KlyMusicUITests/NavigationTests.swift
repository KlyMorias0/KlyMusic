import XCTest

final class NavigationTests: XCTestCase {
    func testRedesignedScreensWithFixtures() {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "dark", "-language", "tr", "-serverURL", "http://127.0.0.1:8879"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Dinle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Türkiye’de şimdi"].waitForExistence(timeout: 15))
        shot(app, "Redesign-Home-Dark")
        tapTab("nav.discover", label: "Keşfet", in: app)
        XCTAssertTrue(app.staticTexts["Türler ve ruh halleri"].waitForExistence(timeout: 5))
        shot(app, "Redesign-Discover-Dark")
        tapTab("nav.library", label: "Kütüphane", in: app)
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        shot(app, "Redesign-Library-Dark")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["Ses kalitesi"].waitForExistence(timeout: 5))
        app.buttons["settings.quality"].tap()
        XCTAssertTrue(app.buttons["settings.quality.high"].waitForExistence(timeout: 5))
        shot(app, "Apple-Quality-Settings")
        app.buttons["settings.quality.high"].tap()
        app.buttons["settings.quality.data"].tap()
        XCTAssertTrue(app.buttons["settings.quality.data"].isSelected)
        app.navigationBars["Ses kalitesi"].buttons.firstMatch.tap()
        shot(app, "Redesign-Settings-Dark")
        app.buttons["settings.theme"].tap()
        XCTAssertTrue(app.buttons["settings.theme.dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.theme.dark"].isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings.theme.")).count, 3)
        shot(app, "Music-Theme-Settings")
        app.navigationBars["Görünüm"].buttons.firstMatch.tap()
        app.buttons["settings.language"].tap()
        XCTAssertTrue(app.buttons["settings.language.tr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.language.tr"].isSelected)
        shot(app, "Music-Language-Settings")
        app.navigationBars["Dil"].buttons.firstMatch.tap()
        let data = app.buttons["settings.data"]
        for _ in 0..<2 { if data.isHittable { break }; app.swipeUp() }
        data.tap()
        XCTAssertTrue(app.buttons["settings.backup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.restore"].exists)
        shot(app, "Music-Library-Data-Settings")
        app.buttons["settings.eraseHistory"].tap()
        let confirm = app.buttons["Geçmişi temizle"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        app.navigationBars["Kütüphane ve Veriler"].buttons.firstMatch.tap()
        let about = app.buttons["settings.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5)); about.tap()
        XCTAssertTrue(app.staticTexts["KlyMusic"].waitForExistence(timeout: 5))
        shot(app, "Music-About-Settings")
        app.navigationBars["Hakkında"].buttons.firstMatch.tap()
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

    func testPlayerMenuAndUpcomingQueue() {
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
        let play = app.buttons["player.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == 'playing'"), evaluatedWith: play)
        waitForExpectations(timeout: 15); play.tap()
        let options = app.buttons.matching(identifier: "track.options.fixture:lyrics").allElementsBoundByIndex
        let visibleOptions = options.first(where: { $0.isHittable })
        XCTAssertNotNil(visibleOptions)
        visibleOptions?.tap()
        XCTAssertTrue(app.buttons["track.options.playlist"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["track.options.next"].exists, "Current-song queue actions must not be shown")
        XCTAssertFalse(app.buttons["track.options.append"].exists)
        shot(app, "26-Player-Menu")
        app.buttons["track.options.playlist"].tap()
        XCTAssertTrue(app.navigationBars["Listeye ekle"].waitForExistence(timeout: 5))
        app.navigationBars["Listeye ekle"].buttons["Vazgeç"].tap()
        app.buttons["player.queue"].tap()
        XCTAssertTrue(app.navigationBars["Çalma sırası"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "queue.current").firstMatch.exists)
        XCTAssertFalse(app.buttons["queue.track.fixture:lyrics"].exists)
        let next = app.buttons["queue.track.fixture:next"]
        XCTAssertTrue(next.exists)
        XCTAssertTrue(app.buttons["queue.track.fixture:third"].exists)
        XCTAssertTrue(app.buttons["queue.track.fixture:last"].exists)
        shot(app, "27-Upcoming-Queue")
        next.tap()
        XCTAssertTrue(app.buttons["queue.track.fixture:next"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["queue.track.fixture:third"].exists, "Selecting a queued song must preserve the following songs")
        XCTAssertFalse(app.buttons["queue.track.fixture:lyrics"].exists)
        app.buttons["queue.options"].tap()
        app.buttons["queue.clear"].tap()
        let clear = app.buttons["Sırayı temizle"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "queue.empty").firstMatch.waitForExistence(timeout: 5))
        shot(app, "28-Queue-Empty")
        app.navigationBars["Çalma sırası"].buttons["Kapat"].tap()
        XCTAssertTrue(app.staticTexts["Sabah Işığı"].firstMatch.exists)
        app.buttons["player.close"].tap()
        tapTab("nav.home", label: "Dinle", in: app)
        XCTAssertTrue(app.staticTexts["Senin için"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["track.row.fixture:next"].exists, "Recently played songs remain available in their own shelf")
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp()
        shot(app, "29-Home-Scrolled-Flat")
        scroll.swipeDown(); scroll.swipeDown()
        shot(app, "30-Home-Top-Flat")
        app.terminate()
    }

    func testAppleStylePagesAndLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "dark", "-language", "tr", "-serverURL", "http://127.0.0.1:8879"]
        app.launch()
        tapTab("nav.library", label: "Kütüphane", in: app)
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        shot(app, "Apple-Library")
        app.buttons["library.options"].tap(); app.buttons["library.edit"].tap()
        let artistsCategory = app.buttons["library.category.artists"]
        XCTAssertTrue(artistsCategory.waitForExistence(timeout: 5)); artistsCategory.tap()
        XCTAssertFalse(artistsCategory.isSelected)
        shot(app, "Music-Library-Edit")
        app.navigationBars["Kütüphaneyi Düzenle"].buttons["Bitti"].tap()
        XCTAssertFalse(app.buttons["library.artists"].exists)
        app.terminate(); app.launch()
        tapTab("nav.library", label: "Kütüphane", in: app)
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.artists"].exists, "Hidden categories must stay hidden after relaunch")
        app.buttons["library.options"].tap(); app.buttons["library.edit"].tap()
        app.buttons["library.category.artists"].tap()
        app.navigationBars["Kütüphaneyi Düzenle"].buttons["Bitti"].tap()
        XCTAssertTrue(app.buttons["library.artists"].waitForExistence(timeout: 5))
        app.buttons["library.options"].tap()
        app.buttons["playlist.create"].tap()
        let name = "Yolculuk \(Int(Date().timeIntervalSince1970))"
        let field = app.textFields["playlist.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        shot(app, "Apple-New-Playlist")
        app.navigationBars["Yeni Çalma Listesi"].buttons["Oluştur"].tap()
        XCTAssertTrue(app.buttons["library.sort"].waitForExistence(timeout: 5))
        app.buttons["library.sort"].tap(); app.buttons["Başlık"].tap()
        XCTAssertTrue(app.staticTexts["Albümler ve Listeler"].waitForExistence(timeout: 5))
        shot(app, "Music-Library-Sort")
        app.buttons["library.sort"].tap(); app.buttons["Son Eklenenler"].tap()
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5)); app.staticTexts[name].tap()
        XCTAssertTrue(app.staticTexts["İlk şarkını ekle"].waitForExistence(timeout: 5))
        shot(app, "Apple-Playlist-Detail")
        tapTab("nav.search", label: "Ara", in: app)
        XCTAssertTrue(app.staticTexts["Kategorilere göz at"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.category.")).firstMatch.waitForExistence(timeout: 10))
        shot(app, "Apple-Search-Categories")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText(name)
        let libraryScope = app.buttons["Kitaplığın"]
        XCTAssertTrue(libraryScope.waitForExistence(timeout: 5)); libraryScope.tap()
        app.scrollViews["search.filters"].swipeLeft()
        let listsFilter = app.buttons["search.filter.playlists"]
        XCTAssertTrue(listsFilter.waitForExistence(timeout: 5)); listsFilter.tap()
        let localList = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.playlist.")).firstMatch
        XCTAssertTrue(localList.waitForExistence(timeout: 5))
        search.typeText("\n")
        shot(app, "Music-Library-Search")
        localList.tap()
        XCTAssertTrue(app.staticTexts["İlk şarkını ekle"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        search.tap()
        search.buttons.firstMatch.tap()
        search.typeText("Gece Yolu")
        app.buttons["KlyMusic"].tap()
        search.typeText("\n")
        XCTAssertTrue(app.buttons["search.filter.albums"].waitForExistence(timeout: 10))
        shot(app, "Apple-Search-Results")
        app.buttons["search.filter.albums"].tap()
        let album = app.buttons["album.open.9002"]
        XCTAssertTrue(album.waitForExistence(timeout: 5)); album.tap()
        XCTAssertTrue(app.buttons["Karıştır"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "Apple-Album-Detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.scrollViews["search.filters"].swipeLeft()
        app.buttons["search.filter.artists"].tap()
        let artist = app.buttons["artist.open.9001"]
        XCTAssertTrue(artist.waitForExistence(timeout: 5)); artist.tap()
        XCTAssertTrue(app.buttons["Takip et"].waitForExistence(timeout: 5) || app.buttons["Takibi bırak"].exists)
        XCTAssertTrue(app.buttons["artist.latest"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["KlyMusic Test"].exists, "Artist name belongs in the hero until it scrolls away")
        shot(app, "Apple-Artist-Detail")
        app.scrollViews.firstMatch.swipeUp(); app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.navigationBars["KlyMusic Test"].waitForExistence(timeout: 5))
        shot(app, "Music-Artist-Scrolled")
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
        let controlsBeforeLyrics = app.buttons["player.playPause"].frame
        app.buttons["lyrics.toggle"].tap()
        let first = app.buttons["lyrics.line.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let controlsWithLyrics = app.buttons["player.playPause"].frame
        XCTAssertEqual(controlsBeforeLyrics.midY, controlsWithLyrics.midY, accuracy: 3, "Lyrics must keep the same player layout")
        XCTAssertEqual(controlsBeforeLyrics.width, controlsWithLyrics.width, accuracy: 3)
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
            app.buttons["library.options"].tap()
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
            shot(app, "Music-Settings-\(theme)")
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
        app.buttons["library.options"].tap()
        app.buttons["playlist.create"].tap()
        let name = "Gece Yolculuğu \(Int(Date().timeIntervalSince1970))"
        let nameField = app.textFields["playlist.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5)); nameField.tap(); nameField.typeText(name)
        app.navigationBars["Yeni Çalma Listesi"].buttons["Oluştur"].tap()
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        app.staticTexts[name].tap()
        XCTAssertTrue(app.staticTexts["İlk şarkını ekle"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        shot(app, "03-Library")
        tapTab("nav.home", label: "Dinle", in: app)
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["Ses kalitesi"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.textFields["settings.server"].exists)
        XCTAssertTrue(app.buttons["settings.about"].exists)
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
