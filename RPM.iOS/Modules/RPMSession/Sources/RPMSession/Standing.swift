import Foundation

/// Where the app is with the account: before the keychain has been read, signed out, reading
/// the first library, or showing it.
public enum AccountStanding: Equatable, Sendable {
    /// Before the keychain has been read. Do not show a sign-in form here. Reading the keychain
    /// is quick, and a signed-in person would otherwise see the form on every launch.
    case starting
    case signedOut
    case loading
    case showing
}

/// What a quota read may do with the account's supporter ground.
///
/// There is no default anywhere this is taken, because a sign-in and a launch need opposite
/// behaviour. See ``LibrarySession/readQuota(_:)``.
public enum GroundRule: Sendable {
    /// A sign-in. Nothing of the account is drawn yet, so the answer is applied at once.
    /// See `SupporterGround.adopt`.
    case adoptNow

    /// The app is already up: a launch that was already signed in, or a refresh. The answer
    /// is written down for the next launch and does not change the screen being read.
    case nextLaunch
}

/// The state of a read that the screens wait on: the wall and the playlists.
public enum ReadStanding: Equatable, Sendable {
    /// The read is out.
    case reading
    case showing
    /// The read failed. The message is shown with a way to ask again.
    case trouble(String)
}

/// Where the station directory stands.
public enum DirectoryStanding: Equatable, Sendable {
    case reading
    case showing
    /// The directory is not answering. Saved stations still play.
    case directoryDown
}
