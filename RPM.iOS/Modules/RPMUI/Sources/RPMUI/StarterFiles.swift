import Foundation
import RPMKit
import RPMLibrary
import RPMAudio

/// Where the starter tracks' files are inside the app (``StarterTracks``): the audio of each
/// track, each record's cover, and the Moonlight Sonata's disc picture.
///
/// They are in this package's `Starter` folder, copied into its bundle as they are. The audio is
/// AAC in an MPEG-4 file at 128 kb/s, which the player's own decoder reads (`StreamedPcm`), made
/// from the desktop's files (`RPM.Desktop/Assets/Sounds/starter-*`). The Apple TV app does not
/// link this package, so it never carries them.
public enum StarterFiles {
    /// The folder in this package's bundle that holds the files.
    private static let folder = "Starter"

    /// The audio file of the starter track `rpmId`, or nil for any other track.
    public static func audio(of rpmId: String) -> URL? {
        guard let record = StarterTracks.record(of: rpmId) else { return nil }
        return file(record.name, "m4a")
    }

    /// The cover or the disc picture of a starter record, or nil for any other record and for a
    /// disc the record does not ship. This is what the artwork store reads them from
    /// (`ArtworkStore.Shipped`).
    public static func picture(_ picture: RecordPicture, of album: CloudAlbum) -> URL? {
        guard let record = StarterTracks.record(of: album) else { return nil }
        switch picture {
        case .cover: return file(record.name, "jpg")
        case .disc: return record.hasDisc ? file(record.name + "-disc", "png") : nil
        }
    }

    private static func file(_ name: String, _ type: String) -> URL? {
        Bundle.module.url(forResource: "starter-" + name, withExtension: type, subdirectory: folder)
    }
}

/// What is on this phone: the starter tracks, which are inside the app, and the downloads. The
/// player reads a track it holds here from the file, without the network and without signing
/// anything, so a starter track is never asked of the cloud and plays offline too.
public struct StarterCopies: PhoneCopies {
    private let downloads: any PhoneCopies

    public init(over downloads: any PhoneCopies) {
        self.downloads = downloads
    }

    public func copy(of rpmId: String) -> PhoneCopy? {
        if let file = StarterFiles.audio(of: rpmId) {
            return PhoneCopy(file: file, kilobits: StarterTracks.kilobits)
        }
        return downloads.copy(of: rpmId)
    }
}
