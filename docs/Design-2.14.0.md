# Music pages — iOS 26 reference

15 November 2026. Reference images are from Apple's explicitly versioned iOS 26 guides:

- [Home](https://support.apple.com/guide/iphone/iph2b1748696/26/ios/26): portrait 3:4 feature cards and square-cover Recently Played shelf.
- [Search](https://support.apple.com/guide/iphone/iph4b506b24d/26/ios/26): full-bleed 16:9 category images, white lower-left labels, native bottom search field.
- [Library](https://support.apple.com/guide/iphone/iph1c41d7ea3/26/ios/26): unboxed red category symbols, regular labels, inset dividers and square collection covers.
- [New](https://support.apple.com/guide/iphone/iph850be8527/26/ios/26): editorial labels above landscape covers and four-row song shelves.

Home, Discover, Search and Library use SwiftUI's inline-large toolbar title so the title and trailing controls share one header row. Existing artwork loads through the same cache. Functional catalog, recent listening, library editing, search filters and settings remain available. Library counts remain available to VoiceOver.

The user explicitly approved changing the player and tab accents to the same Music red (#FA233B). Both shared accent tokens now resolve to that color. The native tab bar, full/mini player, lyrics, artwork renderer and song menu implementations otherwise remain unchanged. KlyMusic retains its own identity and available services. No placeholder radio/account/pinning feature is added. These changes follow the reference layouts; exact pixel identity across devices, content and appearances is not claimed.

The existing UI regression flow captures populated catalog/library screens in light mode; the other populated screen, playback and lyrics flows cover dark mode. Final test results are recorded with the released build, not inferred from source review.
