import Testing
import Foundation
@testable import RPMKit

/// The app key goes on a picture fetched by its address only when the address is the
/// RPM API's. A shelf owner's photo is under profiles/{id}/avatar, which answers 401
/// without the key; a station logo from somebody else's site must never see it.

@Test func aProfilePhotoOnTheApiCarriesTheKey() {
    let photo = URL(string: "https://api.rpmrpmrpm.com/profiles/1245d484/avatar?v=1785707581382")!
    #expect(AppKey.owns(photo))
}

@Test func theHostIsComparedWithoutCase() {
    #expect(AppKey.owns(URL(string: "https://API.rpmrpmrpm.com/profiles/x/avatar")!))
}

@Test func nobodyElseGetsTheKey() {
    #expect(!AppKey.owns(URL(string: "https://rpmrpmrpm.com/logo.png")!))
    #expect(!AppKey.owns(URL(string: "https://accounts.rpmrpmrpm.com/")!))
    #expect(!AppKey.owns(URL(string: "https://api.rpmrpmrpm.com.example.org/avatar")!))
    #expect(!AppKey.owns(URL(string: "https://upload.wikimedia.org/logo.png")!))
}
