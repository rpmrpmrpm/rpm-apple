//
// RPMKit speaks the RPM cloud and accounts API and nothing else. It has no UI
// framework in it on purpose: everything in here is the part that is wrong in
// ways a screenshot cannot show (a refresh margin, a signed URL's lifetime, a
// merge that can empty a playlist), and it is only testable in seconds because
// it builds for macOS. Adding `import UIKit` to this target would end that.
//

public enum RPMKit {
    public static let version = "1"
}
