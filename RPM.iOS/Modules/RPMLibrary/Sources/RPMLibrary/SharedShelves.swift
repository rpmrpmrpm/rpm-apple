import Foundation
import RPMKit

/// The public profile of a person: their name, picture and supporter status.
/// `nobody` is a valid value. It is used for an account that has no display name.
/// Opening the picker again does not change that.
public struct PeerFace: Equatable, Sendable {
    public let displayName: String

    /// The URL of the picture, or `nil` when the person has not set one. This is
    /// the URL, not the image data. Fetching the image is left to the view that
    /// draws it.
    public let avatar: URL?

    public let supporter: Bool

    public init(displayName: String = "", avatar: URL? = nil, supporter: Bool = false) {
        self.displayName = displayName
        self.avatar = avatar
        self.supporter = supporter
    }

    public var isKnown: Bool { !displayName.isEmpty }

    public static let nobody = PeerFace()
}

/// One collection that the library tab can show.
public struct ShelfRow: Identifiable, Equatable, Sendable {
    public let shelf: CloudShelf
    public let name: String
    public let face: PeerFace
    public let isOpen: Bool

    public var isOwn: Bool { shelf.isOwn }
    public var id: String { shelf.ownerId }

    /// The letter shown on a collection's tile when its owner has no picture. This
    /// is the first letter of the person's name. The value is empty when there is no
    /// person to show, and on the user's own row. That row is named "My library",
    /// not after a person, so a letter there would be the collection's initial
    /// standing in for a person.
    public var initial: String {
        guard !isOwn, let first = name.first, first.isLetter || first.isNumber else { return "" }
        return String(first).uppercased()
    }

    /// The supporter mark shown beside a name. **It is never shown on the user's own
    /// row.** The mark tells the user about other people. The user does not need it
    /// on their own collection.
    public var wearsMark: Bool { !isOwn && face.supporter }
}

/// The collections on offer: the user's own, and the ones other people share with
/// them.
///
/// This matches the desktop app's `SharedLibraries.Rows` (RPM.Mobile/Services/
/// SharedLibraries.cs). The function has no side effects, so its rules can be tested
/// directly. The rules are: which row is marked as open, what a nameless account is
/// called, and that the collection the user is viewing stays in the list even when
/// its share has been removed.
public enum SharedShelves {
    /// - Parameters:
    ///   - received: The shares this account has been given.
    ///   - faces: The profile of each owner, keyed by account id. An id with no
    ///     entry means the profile has not loaded yet. This is treated the same as
    ///     an owner who has never published a profile.
    ///   - viewing: The collection the library tab is showing.
    ///   - ownName: The name of the user's own collection.
    ///   - unknownName: The name of a collection whose owner has no profile to read.
    ///     This parameter has no default. The obvious fallback, the account id, is not
    ///     a readable name.
    ///   - ownFace: The profile of the person signed in here. It supplies the picture
    ///     on the own row. This parameter has no default. `nobody` is valid for a
    ///     signed-out user or a profile that has not loaded, so a default would
    ///     silently pick that value. The row keeps the name `ownName`. Only the
    ///     picture comes from `ownFace`.
    public static func rows(
        received: [CloudShare], faces: [String: PeerFace],
        viewing: CloudShelf, ownName: String, unknownName: String, ownFace: PeerFace
    ) -> [ShelfRow] {
        var rows = [ShelfRow(shelf: .own, name: ownName, face: ownFace, isOpen: viewing.isOwn)]

        for share in received where !share.ownerId.isEmpty {
            // Only the profile the owner publishes is used. **The name on the share is the
            // grantee's name**, which is this account on a received share. It does not say
            // whose records these are.
            let face = faces[share.ownerId] ?? .nobody

            rows.append(ShelfRow(shelf: .of(share.ownerId),
                                 name: face.isKnown ? face.displayName : unknownName,
                                 face: face,
                                 isOpen: share.ownerId == viewing.ownerId))
        }

        // A shelf can be open while its share is no longer listed. The share may have
        // been removed, or the list may not have been read yet on this launch. In both
        // cases, the row showing where the user is must still be in the list. Without
        // it, there is no way back from the shelf they are viewing.
        if !viewing.isOwn, !rows.contains(where: { $0.shelf.ownerId == viewing.ownerId }) {
            let face = faces[viewing.ownerId] ?? .nobody

            rows.append(ShelfRow(shelf: viewing,
                                 name: face.isKnown ? face.displayName : unknownName,
                                 face: face, isOpen: true))
        }

        return rows
    }
}
