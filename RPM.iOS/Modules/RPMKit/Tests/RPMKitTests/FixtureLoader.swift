import Foundation
import Testing
@testable import RPMKit

/// Fixtures are the contract. Nothing in Swift is compiled against the .NET
/// records, so a captured response is the only thing that notices when
/// a Lambda changes shape, and it notices here rather than on a phone.
func fixtureData(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "fixture \(name).json is missing"
    )
    return try Data(contentsOf: url)
}

func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    try RPMJSON.decoder.decode(type, from: fixtureData(name))
}
