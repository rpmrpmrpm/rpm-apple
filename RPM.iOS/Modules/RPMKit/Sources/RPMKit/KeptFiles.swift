import Foundation

/// The folder where this app keeps its small state files between launches: the catalogue copy,
/// the play log, and the saved stations.
///
/// Application Support on the phone and the Mac. On tvOS, the Caches folder. An Apple TV app has
/// no persistent local storage outside about 500 KB of user defaults, and the system can empty
/// Caches when it needs space. Every store kept here treats a missing file as an empty store, so
/// a cleared folder makes the next launch slower but does not break anything.
public enum KeptFiles {
    public static var folder: URL {
        #if os(tvOS)
        let place = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let place = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        let base = (try? FileManager.default.url(for: place, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
    }
}
