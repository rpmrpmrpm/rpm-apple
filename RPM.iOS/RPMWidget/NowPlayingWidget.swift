import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// The home screen widgets of the iPhone app. There is one: what is playing.
@main
struct RPMWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

/// What is playing, with the previous, play and pause, and next keys. Landscape only (the medium
/// size). The app writes what it shows (``WidgetCard``) and asks for it to be drawn again when the
/// song, the cover or the play state changes, so the timeline has one entry and never renews
/// itself.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCard.kind, provider: NowPlayingTimeline()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        // The app's name, which is the same in every language.
        .configurationDisplayName("rpm")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// One drawing of the widget. The pictures are kept as JPEG data, so the entry is `Sendable`.
struct NowPlayingEntry: TimelineEntry, Sendable {
    let date: Date
    let card: WidgetCard?
    let cover: Data?
    let backdrop: Data?

    /// What the app wrote last, read from the shared folder.
    static func read() -> NowPlayingEntry {
        NowPlayingEntry(date: .now, card: WidgetShelf.readCard(),
                        cover: WidgetShelf.coverFile.flatMap { try? Data(contentsOf: $0) },
                        backdrop: WidgetShelf.backdropFile.flatMap { try? Data(contentsOf: $0) })
    }

    /// Nothing played yet: the wordmark on a dark ground.
    static let empty = NowPlayingEntry(date: .now, card: nil, cover: nil, backdrop: nil)
}

struct NowPlayingTimeline: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        .empty
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(.read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [.read()], policy: .never))
    }
}

/// The widget: the cover on the left, the title and the artist on the right with the three keys
/// under them, and the dimmed rpm wordmark in the top right corner. The ground is the cover,
/// blurred. A tap anywhere but on a key opens the app.
struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry

    /// The space round the widget's content and between the cover and the words.
    private static let margin: CGFloat = 14

    var body: some View {
        HStack(spacing: Self.margin) {
            cover
            if let card = entry.card {
                VStack(alignment: .leading, spacing: 0) {
                    words(card)
                    Spacer(minLength: 6)
                    keys(card)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(Self.margin)
        .overlay(alignment: .topTrailing) {
            wordmark
                .padding(.top, Self.margin)
                .padding(.trailing, Self.margin + 2)
        }
        .containerBackground(for: .widget) { ground }
        .widgetURL(URL(string: "rpm://now-playing"))
    }

    /// The cover, square, as tall as the widget's content.
    private var cover: some View {
        Group {
            if let picture = entry.cover.flatMap(UIImage.init(data:)) {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    /// The title and the artist. They stop short of the wordmark.
    private func words(_ card: WidgetCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(.custom("Cabin-Bold", size: 17))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(card.artist)
                .font(.custom("Cabin-Medium", size: 14))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.top, 2)
        .padding(.trailing, 44)
    }

    /// The previous, play or pause, and next keys, spread over the width of the words.
    private func keys(_ card: WidgetCard) -> some View {
        HStack(spacing: 0) {
            key(WidgetPreviousIntent(), symbol: "backward.fill", size: 19, name: card.previous)
            key(WidgetPlayPauseIntent(), symbol: card.playing ? "pause.fill" : "play.fill", size: 25,
                name: card.playPause)
            key(WidgetNextIntent(), symbol: "forward.fill", size: 19, name: card.next)
        }
    }

    private func key<Intent: AppIntent>(_ intent: Intent, symbol: String, size: CGFloat,
                                        name: String) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    /// The rpm wordmark, small and at half strength.
    private var wordmark: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: 12)
            .foregroundStyle(.white.opacity(0.5))
    }

    /// The cover, blurred by the app, darkened so the white words read on a light cover.
    private var ground: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
            if let picture = entry.backdrop.flatMap(UIImage.init(data:)) {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
            }
            Color.black.opacity(0.32)
        }
    }
}
