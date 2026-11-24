import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// What the accounts service says about the account after it took a store purchase: the supporter
/// fields of `/auth/me`. The server type is `SupporterStanding` in rpm.Api.
public struct SupporterAnswer: Decodable, Equatable, Sendable {
    public let grSupporter: Bool
    public let grSupporterUntil: Int64
    /// `apple` or `google` while that store pays the longest, else nil.
    public let grSupporterStore: String?
    public let grUnlimitedStorage: Bool
    public let grTester: Bool

    public init(grSupporter: Bool, grSupporterUntil: Int64, grSupporterStore: String?,
                grUnlimitedStorage: Bool, grTester: Bool) {
        self.grSupporter = grSupporter
        self.grSupporterUntil = grSupporterUntil
        self.grSupporterStore = grSupporterStore
        self.grUnlimitedStorage = grUnlimitedStorage
        self.grTester = grTester
    }
}

/// How the accounts service answered a store purchase.
public enum SupporterPost: Equatable, Sendable {
    /// The service checked the purchase with Apple and stored it.
    case confirmed(SupporterAnswer)
    /// The subscription belongs to another rpm account. Nothing changed.
    case otherAccount
    /// Not a signed purchase of an rpm supporter subscription. Sending it again changes nothing.
    case refused
    /// The service could not be reached, could not store it, or the app is not signed in. The
    /// purchase is sent again later.
    case unavailable

    /// Whether the service has decided about this transaction. Only then is it finished.
    var settles: Bool { self != .unavailable }
}

/// Where the phone sends a transaction that Apple signed. ``SupporterClient`` is the only
/// implementation; tests replace it.
public protocol SupporterPosting: Sendable {
    func postApple(signedTransaction: String) async -> SupporterPost
}

/// `POST supporter/apple` on the accounts service, with the account's token.
public struct SupporterClient: SupporterPosting {
    private let transport: Transport

    /// - Parameter transport: built on the accounts service's address, not the API's.
    public init(transport: Transport) {
        self.transport = transport
    }

    public func postApple(signedTransaction: String) async -> SupporterPost {
        do {
            let (status, data) = try await transport.raw(
                "POST", "supporter/apple", body: ["signedTransaction": signedTransaction],
                cache: .reloadIgnoringLocalCacheData)
            return Self.read(status: status, data: data)
        } catch {
            return .unavailable
        }
    }

    /// The service's answer. A 409 for a deleted account (`noAccount`) is not the other-account case:
    /// it is left to be sent again, like any answer this cannot act on.
    static func read(status: Int, data: Data) -> SupporterPost {
        struct Refusal: Decodable { let error: String? }

        switch status {
        case 200..<300:
            guard let answer = try? RPMJSON.decoder.decode(SupporterAnswer.self, from: data) else { return .unavailable }
            return .confirmed(answer)
        case 409:
            return (try? RPMJSON.decoder.decode(Refusal.self, from: data))?.error == "otherAccount" ? .otherAccount : .unavailable
        case 400:
            return .refused
        default:
            return .unavailable
        }
    }
}

/// One transaction to send: what Apple signed, and how to finish it with StoreKit.
public struct HeldTransaction: Sendable {
    public let signed: String
    public let finish: @Sendable () async -> Void

    public init(signed: String, finish: @escaping @Sendable () async -> Void) {
        self.signed = signed
        self.finish = finish
    }
}

/// The App Store subscription on this phone and the accounts service.
///
/// The service, not the phone, decides who is a supporter: the phone sends what Apple signed and
/// the service checks it with Apple. A transaction is finished only after the service answered.
/// StoreKit delivers an unfinished transaction again, and every launch and return to the
/// foreground sends the current subscription (``sync(onConfirmed:)``), so a purchase made with no
/// network reaches the service later.
public actor SupporterStore {
    /// The App Store subscription group "Supporter (rpm)".
    public static let groupID = "22613550"

    /// The subscriptions in the group: month, year and week. rpm.Api accepts these and no others;
    /// change both together.
    public static let products: Set<String> = ["rpm0001", "rpm0002", "rpm0003"]

    private let client: any SupporterPosting

    public init(client: any SupporterPosting) {
        self.client = client
    }

    /// The string key of the line the supporter card shows after a sync, or nil. A restore of a
    /// subscription that another rpm account owns reaches the service only through a sync, so the sync
    /// is where the person is told.
    public static func noteKey(for posts: [SupporterPost]) -> String? {
        posts.contains(.otherAccount) ? "Supporter_OtherAccount" : nil
    }

    /// Sends one transaction, and finishes it when the service has decided about it.
    public func send(_ held: HeldTransaction) async -> SupporterPost {
        let said = await client.postApple(signedTransaction: held.signed)
        if said.settles { await held.finish() }
        return said
    }

    #if canImport(StoreKit)
    /// Sends a transaction StoreKit reported. One Apple could not verify on the phone, or one for
    /// another product, is not sent.
    public func send(_ result: VerificationResult<Transaction>) async -> SupporterPost? {
        guard case .verified(let transaction) = result, Self.products.contains(transaction.productID) else { return nil }
        return await send(HeldTransaction(signed: result.jwsRepresentation, finish: { await transaction.finish() }))
    }

    /// Listens for renewals, refunds, Ask to Buy approvals and purchases made on another device, for
    /// the life of the app. Started once, at launch.
    public func listen(onConfirmed: @escaping @Sendable (SupporterAnswer) async -> Void) -> Task<Void, Never> {
        Task {
            for await update in Transaction.updates {
                if case .confirmed(let answer)? = await send(update) { await onConfirmed(answer) }
            }
        }
    }

    /// Sends the subscription this Apple Account has now, and any transaction left unfinished. At
    /// launch after sign-in, on return to the foreground, and when the subscription sheet closes,
    /// which covers Restore.
    /// - Returns: how the service answered each transaction sent.
    @discardableResult
    public func sync(onConfirmed: @escaping @Sendable (SupporterAnswer) async -> Void) async -> [SupporterPost] {
        var sent = Set<UInt64>()
        var said: [SupporterPost] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result { sent.insert(t.id) }
            guard let post = await send(result) else { continue }
            said.append(post)
            if case .confirmed(let answer) = post { await onConfirmed(answer) }
        }
        for await result in Transaction.unfinished {
            if case .verified(let t) = result, sent.contains(t.id) { continue }
            guard let post = await send(result) else { continue }
            said.append(post)
            if case .confirmed(let answer) = post { await onConfirmed(answer) }
        }
        return said
    }
    #endif
}

/// What the iPhone offers on the supporter card.
public enum SupporterOffer: Equatable, Sendable {
    /// The account does not pay: the subscription sheet. A closed beta tester has the features but
    /// does not pay, so is offered it too.
    case become
    /// The App Store pays: the App Store's own page to change or cancel the subscription.
    case manageInAppStore
    /// Stripe, Google Play or a grant pays. It is managed there, and the iPhone does not link to it.
    case nothing
}

extension CloudQuota {
    public var supporterOffer: SupporterOffer {
        guard wearsMark else { return .become }
        return store == "apple" ? .manageInAppStore : .nothing
    }
}
