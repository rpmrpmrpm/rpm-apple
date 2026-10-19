import Foundation

/// The receiver namespace: what is running on the speaker, and how loud it is.
extension CastLink {
    public enum Refused: Error, Equatable {
        /// The receiver answered, and it said no.
        case launch(reason: String, speaker: String)

        /// It answered with something that is not a status.
        case unreadable
    }

    /// What the receiver is doing now.
    public func status() async throws -> ReceiverStatus {
        let answer = try await ask(#"{"type":"GET_STATUS"}"#, namespace: Self.receiverNamespace)

        guard let status = ReceiverStatus.of(answer.payload) else { throw Refused.unreadable }
        return status
    }

    /// Starts an app on the speaker, and opens a connection to it.
    ///
    /// **Opening the connection to the app is part of launching it.** It is not a separate step that a
    /// caller might forget. A receiver drops every message sent to a transport it is not connected to,
    /// and it does not say so.
    ///
    /// An app that is already running is joined, not started again. Launching over a live session would
    /// interrupt the queue that the app is playing.
    @discardableResult
    public func launch(_ appId: String = ReceiverStatus.defaultMediaReceiver)
    async throws -> ReceiverStatus.Application {
        if let running = try await status().applications.first(where: { $0.appId == appId }) {
            try await connect(to: running.transportId)
            return running
        }

        let answer = try await ask(#"{"type":"LAUNCH","appId":"\#(appId)"}"#,
                                   namespace: Self.receiverNamespace,
                                   within: .seconds(20))

        if answer.payload.contains("LAUNCH_ERROR") {
            throw Refused.launch(reason: Self.reason(in: answer.payload) ?? "",
                                 speaker: name)
        }

        guard let status = ReceiverStatus.of(answer.payload),
              let app = status.applications.first(where: { $0.appId == appId })
        else { throw Refused.unreadable }

        try await connect(to: app.transportId)
        return app
    }

    /// Stops the app. This is what gives the speaker back.
    public func stop(_ sessionId: String) async throws {
        _ = try await ask(#"{"type":"STOP","sessionId":"\#(sessionId)"}"#,
                          namespace: Self.receiverNamespace)
    }

    /// Sets the room's volume, from 0 to 1.
    ///
    /// The level is the **room's**, not the track's. It changes the speaker itself, so someone standing next to
    /// it hears the change without the phone. A device whose `controlType` is `fixed` is wired into an amplifier
    /// that controls the volume. A level set on one of those does nothing, and gives no error. That is why the
    /// status is read before the volume is offered.
    @discardableResult
    public func setVolume(_ level: Double) async throws -> ReceiverStatus {
        let wanted = min(1, max(0, level))
        let answer = try await ask(#"{"type":"SET_VOLUME","volume":{"level":\#(wanted)}}"#,
                                   namespace: Self.receiverNamespace)

        guard let status = ReceiverStatus.of(answer.payload) else { throw Refused.unreadable }
        return status
    }

    @discardableResult
    public func mute(_ muted: Bool) async throws -> ReceiverStatus {
        let answer = try await ask(#"{"type":"SET_VOLUME","volume":{"muted":\#(muted)}}"#,
                                   namespace: Self.receiverNamespace)

        guard let status = ReceiverStatus.of(answer.payload) else { throw Refused.unreadable }
        return status
    }

    /// The reason text in a refusal, if there is one.
    static func reason(in payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return fields["reason"] as? String
    }
}
