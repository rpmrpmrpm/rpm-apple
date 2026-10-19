import Foundation

/// The app's own pages on the web.
///
/// The Swift half of `RPM.Core.Cloud.RpmSite`. It exists for the same reason: both apps link to the
/// same pages and must not be able to point at different ones. The profile tab links to the
/// supporter page and the About screen links to the other three. If a page moves, it is changed
/// here once and not in every screen that links to it.
///
/// It lives in `RPMKit` so that every other module can use it, in the same way as `Loc`.
public enum RpmSite {
    /// The site itself.
    public static let home = URL(string: "https://rpmrpmrpm.com")!

    /// Where a listener goes for help.
    public static let support = URL(string: "https://rpmrpmrpm.com/support")!

    /// What the app does with what it is told.
    public static let privacy = URL(string: "https://rpmrpmrpm.com/privacy")!

    /// The terms of use, which include the licence for the apps.
    public static let terms = URL(string: "https://rpmrpmrpm.com/terms")!

    /// Where a listener buys support for rpm. What is sold there, and what the account can then use,
    /// is decided by the accounts service. This is only the link.
    public static let becomeSupporter = URL(string: "https://rpmrpmrpm.com/become-supporter")!
}
