import Foundation

/// The app's own pages on the web.
///
/// The Swift half of `RPM.Core.Cloud.RpmSite`. It exists for the same reason: both apps link to the
/// same pages and must not be able to point at different ones. The About screen and the
/// subscription sheet link to them. If a page moves, it is changed here once and not in every
/// screen that links to it. The iPhone app sells supporter status through the App Store and links
/// to no payment page (App Store rule 3.1.1).
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

    /// The password reset page for an email account. The page mails a link where the person chooses
    /// a new password. The TV's sign-in screen shows it as a QR code. The iPhone does not open it:
    /// its sign-in screen resets the password in the app, with a mailed code.
    public static let forgotPassword = URL(string: "https://rpmrpmrpm.com/forgot-password")!
}
