import Foundation
import Testing
@testable import RPMSession

@Suite struct PlayDeviceTests {
    private func store() -> UserDefaults {
        let name = "rpm.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func theNameIsKeptOnceMade() {
        let device = PlayDevice(store: store())
        let first = device.id
        #expect(!first.isEmpty)
        #expect(device.id == first)
    }

    @Test func forgettingMakesANewName() {
        let device = PlayDevice(store: store())
        let first = device.id
        device.forget()
        #expect(device.id != first)
    }

    @Test func theNameIsReadFromTheKeyThePhoneUsed() {
        let defaults = store()
        defaults.set("held-before", forKey: "plays.device")
        #expect(PlayDevice(store: defaults).id == "held-before")
    }
}
