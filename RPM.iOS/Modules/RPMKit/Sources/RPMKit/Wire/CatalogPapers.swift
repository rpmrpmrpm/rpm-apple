import Foundation

/// What `metadata/papers` answers: the act and the record as the catalogues have them.
///
/// The phone's reading of `CatalogPapers` in `RPM.Fingerprint/Catalog/CatalogContracts.cs`, cut
/// down to the fields it uses: the name, the Wikidata entity and the links, which is what the
/// Wikipedia article is found with. Every field is optional here. The server omits what it does
/// not know, and a record the catalogues have never heard of is an ordinary answer.
public struct CatalogPapers: Decodable, Sendable, Equatable {
    public let artist: CatalogArtist?
    public let album: CatalogAlbum?

    public init(artist: CatalogArtist? = nil, album: CatalogAlbum? = nil) {
        self.artist = artist
        self.album = album
    }
}

public struct CatalogArtist: Decodable, Sendable, Equatable {
    public let name: String?
    public let wikidataId: String?
    public let links: [CatalogLink]?

    public init(name: String?, wikidataId: String? = nil, links: [CatalogLink]? = nil) {
        self.name = name
        self.wikidataId = wikidataId
        self.links = links
    }
}

public struct CatalogAlbum: Decodable, Sendable, Equatable {
    public let title: String?
    public let links: [CatalogLink]?

    public init(title: String?, links: [CatalogLink]? = nil) {
        self.title = title
        self.links = links
    }
}

/// One outside page. `relation` is the catalogue's label for it ("official homepage",
/// "wikidata"); the phone decides by the host, as the desktop does.
public struct CatalogLink: Decodable, Sendable, Equatable {
    public let url: String
    public let relation: String?

    public init(url: String, relation: String? = nil) {
        self.url = url
        self.relation = relation
    }
}
