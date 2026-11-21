import Foundation
import Observation
#if os(iOS) || os(tvOS)
import AVFAudio
#endif

/// The speakers an equaliser curve belongs to, as on the desktop (EqProfile.Device): each set of
/// speakers keeps its own curve, because a curve is a correction for the speakers and not a taste.
/// The phone's speaker needs bass, good headphones need none, and a Bluetooth speaker needs something
/// else again.
///
/// `key` is what the curve is stored under: two headphones of different models have different keys.
/// `label` is the speakers' name as the phone gives it, shown over the faders; nil while casting.
public struct EqOutput: Sendable, Equatable {
    public let key: String
    public let label: String?

    public init(key: String, label: String?) {
        self.key = key
        self.label = label
    }

    public var casting: Bool { key == Self.castKey }

    static let castKey = "cast"

    /// A speaker in another room, or AirPlay: one curve for all of them, as on the desktop.
    public static let cast = EqOutput(key: castKey, label: nil)

    /// The kinds of output the phone can play through.
    public enum Kind: String, Sendable {
        /// The phone's own speaker or earpiece.
        case speaker
        case bluetooth
        case wired
        case usb
        case hdmi
        case car
        /// AirPlay: the sound leaves the phone, as a cast does.
        case airPlay
        case other
    }

    /// Which curve the music uses: the cast curve while casting or on AirPlay, the one curve of the
    /// phone's speaker, or the curve of the named device of its kind. `name` is the device's name as
    /// the phone gives it.
    public static func pick(kind: Kind, name: String, casting: Bool) -> EqOutput {
        if casting || kind == .airPlay { return .cast }
        // The phone has one speaker, whatever name it is given.
        if kind == .speaker { return EqOutput(key: Kind.speaker.rawValue, label: name) }
        return EqOutput(key: kind.rawValue + ":" + name, label: name)
    }
}

/// The equaliser, as on the desktop (EqService) and the Android phone: one curve for each set of
/// speakers (``EqOutput``), each stored under ``prefix`` and the speakers' key. A set of speakers seen
/// for the first time starts flat and off. The curve of the speakers the music goes to now is the one
/// the player hears (``Player/equalizer``), so a change is heard on the music already playing.
///
/// The phone makes one and keeps it for the life of the app; the Apple TV makes none, so its sound
/// is never changed.
@MainActor
@Observable
public final class EqualizerSettings {
    /// Where each curve is kept, in front of the speakers' key.
    static let prefix = "eq.curve."

    /// The speakers the music goes to now, whose curve is on the faders. Nil until ``start()``.
    public private(set) var output: EqOutput?

    /// The curve of ``output``, as on the faders and in the player.
    public private(set) var curve = EqCurve.off

    private let player: Player
    private let store: UserDefaults

    @ObservationIgnored private var listening: NSObjectProtocol?

    public init(player: Player, store: UserDefaults = .standard) {
        self.player = player
        self.store = store
    }

    /// Follows the speakers from now on: a device connected or disconnected, and AirPlay. A cast to
    /// a speaker in another room is told by ``follow()``, which the owner calls when it starts and
    /// ends.
    public func start() {
        #if os(iOS) || os(tvOS)
        if listening == nil {
            // No queue, and a hop with a task: the session posts from its own thread. See
            // `RemoteControl.watchTheSession`.
            listening = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.follow() }
            }
        }
        #endif
        follow()
    }

    /// Looks again at where the music goes. When it is other speakers than before, their own curve
    /// is shown and heard.
    public func follow() {
        let now = EqOutput.pick(kind: Self.kind, name: Self.name, casting: player.isCasting)
        let before = output
        output = now
        guard before?.key != now.key else { return }
        curve = EqCurve.parse(store.string(forKey: Self.prefix + now.key))
        player.equalizer = curve
    }

    /// The curve is changed only here, so what is stored, what is shown and what is heard cannot
    /// disagree.
    public func change(_ next: EqCurve) {
        guard let output, next != curve else { return }
        curve = next
        player.equalizer = next
        store.set(next.stored, forKey: Self.prefix + output.key)
    }

    // ── the route ──

    #if os(iOS) || os(tvOS)
    /// The first output of the session's route: where the music goes, or would go.
    private static var route: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first
    }

    private static var kind: EqOutput.Kind {
        guard let port = route?.portType else { return .speaker }
        switch port {
        case .builtInSpeaker, .builtInReceiver: return .speaker
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return .bluetooth
        case .headphones, .lineOut: return .wired
        case .usbAudio: return .usb
        case .HDMI: return .hdmi
        case .carAudio: return .car
        case .airPlay: return .airPlay
        default: return .other
        }
    }

    private static var name: String { route?.portName ?? "" }
    #else
    private static var kind: EqOutput.Kind { .speaker }
    private static var name: String { "" }
    #endif
}
