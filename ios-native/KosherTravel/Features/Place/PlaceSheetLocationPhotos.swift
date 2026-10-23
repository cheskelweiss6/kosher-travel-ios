import Foundation

/// The website's curated photos for a named place (src/locationPhotos.ts CURATED_LOCATION_PHOTOS, Oct 23 2026),
/// used by the place sheet only when the listing has no photo of its own (PlaceDetailsModal.tsx:183-203).
/// An empty string is the website's NO_PHOTO_PLACEHOLDER (the navy "no verified photo yet" tile). The category
/// photo pools on the website are empty since the Oct 18 2026 photo audit, so nothing else is looked up.
enum PlaceSheetLocationPhotos {
    /// Same order as the website's object (its substring rule takes the first key that matches).
    static let curated: [(String, [String])] = [
        ("antigua guatemala", ["https://kosher-travel-img.sites.tab.bot/wm/5cdc4fb724e8ca84.webp", "https://kosher-travel-img.sites.tab.bot/wm/b8acdab9400b2157.webp"]),
        ("albertsons (jackson hole)", [""]),
        ("albertsons jackson hole kosher", [""]),
        ("albertsons kosher corner", [""]),
        ("chabad of mobile / south alabama", []),
        ("chabad of mobile", []),
        ("hen house market (kosher deli & bakery)", [""]),
        ("the grove kosher food market", [""]),
        ("mount royal fine foods kosher", [""]),
        ("smith’s summerlin kosher", [""]),
        ("smith's summerlin kosher", [""]),
        ("smith’s santa fe kosher", [""]),
        ("smith's santa fe kosher", [""]),
        ("kosher frederick", [""]),
        ("atkinson’s market kosher", [""]),
        ("atkinson's market kosher", [""]),
        ("manhattan avenue deli", [""]),
        ("harmons st. george kosher corner", [""]),
        ("harmons st. george", [""]),
        ("hen house supermarket kosher section", [""]),
        ("hen house market", [""]),
        ("country mart kosher corner", [""]),
        ("dan’s supermarket kosher section", [""]),
        ("dan's supermarket kosher section", [""]),
        ("heinen’s of beachwood section", [""]),
        ("heinen's of beachwood section", [""]),
        ("metro market kosher department", [""]),
        ("birmingham botanical gardens", []),
        ("birmingham civil rights institute", []),
        ("vulcan park and museum", ["https://kosher-travel-img.sites.tab.bot/wm/467b9d7aea90280b.webp"]),
        ("uss alabama battleship memorial park", ["https://kosher-travel-img.sites.tab.bot/wm/a3858c23c91e4dfb.webp"]),
        ("mobile botanical gardens", []),
        ("mobile museum of art", ["https://www.mobilemuseumofart.com/wp-content/uploads/2026/09/front-view-mmoa.jpg"]),
        ("mendenhall glacier recreation area", ["https://kosher-travel-img.sites.tab.bot/wm/4679be161aa3800e.webp"]),
        ("mount roberts tramway", ["https://kosher-travel-img.sites.tab.bot/wm/0f3c4313fd263cec.webp"]),
        ("alyeska aerial tramway", []),
        ("virgin creek falls trail", []),
        ("denali glacier landing flightseeing", []),
        ("talkeetna river walk", ["https://kosher-travel-img.sites.tab.bot/wm/c713c0169b13644a.webp"]),
        ("savage river scenic loop trail", ["https://kosher-travel-img.sites.tab.bot/wm/56a16c3fb94ad52f.webp"]),
        ("denali park road transit tour", ["https://kosher-travel-img.sites.tab.bot/wm/d5c8a7161f4fdb61.webp"]),
        ("worthington glacier state recreation site", ["https://kosher-travel-img.sites.tab.bot/wm/09b2981db7422384.webp"]),
        ("worthington glacier", ["https://kosher-travel-img.sites.tab.bot/wm/09b2981db7422384.webp"]),
        ("keystone canyon waterfalls", ["https://kosher-travel-img.sites.tab.bot/wm/10056226e6834287.webp"]),
        ("historic creek street boardwalk", []),
        ("creek street", []),
        ("misty fjords national monument floatplane tour", ["https://kosher-travel-img.sites.tab.bot/wm/7ff69d1dac853f75.webp"]),
        ("white pass & yukon route railroad", []),
        ("white pass & yukon route railway", []),
        ("sitka national historical park totem walk", ["https://kosher-travel-img.sites.tab.bot/wm/7c9c06dfef8c3c66.webp"]),
        ("sitka national historical park", ["https://kosher-travel-img.sites.tab.bot/wm/7c9c06dfef8c3c66.webp"]),
        ("historic russian bishop's house", ["https://kosher-travel-img.sites.tab.bot/wm/1030ee0998ba4c04.webp"]),
        ("historic russian bishop’s house", ["https://kosher-travel-img.sites.tab.bot/wm/1030ee0998ba4c04.webp"]),
        ("the homer spit", ["https://kosher-travel-img.sites.tab.bot/wm/de07cc0fdcc7fa2e.webp"]),
        ("homer spit", ["https://kosher-travel-img.sites.tab.bot/wm/de07cc0fdcc7fa2e.webp"]),
        ("portage pass glacier hiking trail", ["https://kosher-travel-img.sites.tab.bot/wm/fdb3e297e935b768.webp"]),
        ("portage pass", ["https://kosher-travel-img.sites.tab.bot/wm/fdb3e297e935b768.webp"]),
        ("tony knowles coastal trail", []),
        ("griffith observatory", ["https://kosher-travel-img.sites.tab.bot/wm/53b44f936b7eebdf.webp"]),
        ("santa monica pier", []),
        ("desert botanical garden", ["https://kosher-travel-img.sites.tab.bot/wm/f8c626a3f6b1589f.webp"]),
        ("camelback mountain trail", []),
        ("old town scottsdale", []),
        ("cathedral rock trail", ["https://kosher-travel-img.sites.tab.bot/wm/3cde9b096e5f3f85.webp"]),
        ("red rock scenic byway", ["https://kosher-travel-img.sites.tab.bot/wm/ed3f32c8d6833a6e.webp"]),
        ("san francisco peaks scenic skyride", ["https://kosher-travel-img.sites.tab.bot/wm/ca1e17f4eb93963e.webp"]),
        ("antelope canyon slot tour", ["https://kosher-travel-img.sites.tab.bot/wm/12c3661aaf1ac0c6.webp"]),
        ("horseshoe bend overlook", ["https://kosher-travel-img.sites.tab.bot/wm/b541c3373a2cfd6a.webp"]),
        ("saguaro national park", []),
        ("casa grande ruins national monument", ["https://kosher-travel-img.sites.tab.bot/wm/b618ede5470ccd90.webp"]),
        ("pinnacle mountain state park", ["https://kosher-travel-img.sites.tab.bot/wm/460324bf5371e389.webp"]),
        ("big dam bridge", ["https://kosher-travel-img.sites.tab.bot/wm/f1ae0b721036cbab.webp"]),
        ("arkansas state capitol", ["https://kosher-travel-img.sites.tab.bot/wm/63f31bfad35a31c0.webp"]),
        ("little rock central high school", ["https://kosher-travel-img.sites.tab.bot/wm/f0bd24d9a252040a.webp"]),
        ("little rock central high school national historic site", ["https://kosher-travel-img.sites.tab.bot/wm/f0bd24d9a252040a.webp"]),
        ("arkansas museum of fine arts", []),
        ("devil's den state park", []),
        ("crystal bridges museum of american art", ["https://kosher-travel-img.sites.tab.bot/wm/dabc6da0a4f5368a.webp"]),
        ("old main", []),
        ("fayetteville historic square", []),
        ("wilson park", ["https://kosher-travel-img.sites.tab.bot/wm/8a684736fdf9b4eb.webp"]),
        ("shallots bistro", ["https://dottie.enjoyillinois.com/assets/Tourism-Operators/images/shallots__FocusFillWyIwLjAwIiwiMC4wMCIsMjAwMCw5NTBd.jpg"]),
        ("shallots", ["https://dottie.enjoyillinois.com/assets/Tourism-Operators/images/shallots__FocusFillWyIwLjAwIiwiMC4wMCIsMjAwMCw5NTBd.jpg"]),
        ("kosher cajun new york deli & grocery", []),
        ("kosher cajun", []),
        ("central park", []),
        ("the metropolitan museum of art", []),
        ("the metropolitan museum of art (the met)", []),
        ("metropolitan museum of art", []),
        ("courtyard by marriott isla verde beach resort", []),
        ("condado vanderbilt hotel", []),
        ("condado vanderbilt", []),
        ("caribe hilton", ["https://kosher-travel-img.sites.tab.bot/wm/203d256347bbafc0.webp"]),
    ]

    private static let byName: [String: [String]] = {
        var d: [String: [String]] = [:]
        for (k, v) in curated where d[k] == nil { d[k] = v }
        return d
    }()

    /// web resolveLocationPhotos(name): the exact name first, then a curated key of 8+ letters inside a name of 8+
    /// letters. nil when the website has nothing curated for it.
    static func resolve(_ name: String) -> [String]? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return nil }
        if let hit = byName[n] { return hit }
        if n.count >= 8 {
            for (k, v) in curated where k.count >= 8 && n.contains(k) { return v }
        }
        return nil
    }
}
