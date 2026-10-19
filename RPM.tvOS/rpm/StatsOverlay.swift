import SwiftUI
import QuartzCore
import Darwin
import RPMKit

/// Performance stats, drawn at the top left over everything while the setting is on. They show
/// frames per second, how many frames were late and the slowest one, the same counts since the
/// stats were turned on, the app's CPU use and its memory.
struct StatsOverlay: View {
    @State private var counter = FrameCounter()

    var body: some View {
        let now = counter.now
        VStack(alignment: .leading, spacing: 4) {
            Text(Loc.get("Tv_StatsNow", String(now.fps), String(now.late), String(now.slowest)))
            Text(Loc.get("Tv_StatsSince", String(counter.frames), String(counter.lateTotal),
                         String(counter.frames > 0 ? counter.lateTotal * 100 / counter.frames : 0)))
            Text(Loc.get("Tv_StatsCpu", String(now.cpu)))
            Text(Loc.get("Atv_StatsMemory", String(now.memory)))
        }
        .font(.tv(20).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(14)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
        .onAppear { counter.start() }
        .onDisappear { counter.stop() }
    }
}

/// Counts the display's frames with a display link. It also reads the app's CPU and memory once a
/// second.
@MainActor
@Observable
final class FrameCounter {
    struct Second: Equatable {
        var fps = 0, late = 0, slowest = 0, cpu = 0, memory = 0
    }

    private(set) var now = Second()
    private(set) var frames = 0
    private(set) var lateTotal = 0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var secondStart: CFTimeInterval = 0
    @ObservationIgnored private var counting = Second()
    @ObservationIgnored private var cpuAt: (wall: CFTimeInterval, used: Double) = (0, 0)

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func frame(_ link: CADisplayLink) {
        let t = link.timestamp
        defer { last = t }
        guard last > 0 else { secondStart = t; return }
        let gap = t - last
        let budget = link.targetTimestamp - link.timestamp
        counting.fps += 1
        frames += 1
        if gap > max(budget, 1.0 / 60) * 1.5 {
            counting.late += 1
            lateTotal += 1
        }
        counting.slowest = max(counting.slowest, Int(gap * 1000))
        if t - secondStart >= 1 {
            counting.cpu = cpuPercent(wall: t)
            counting.memory = Self.memoryMB()
            now = counting
            counting = Second()
            secondStart = t
        }
    }

    private func cpuPercent(wall: CFTimeInterval) -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let used = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        defer { cpuAt = (wall, used) }
        guard cpuAt.wall > 0, wall > cpuAt.wall else { return 0 }
        return Int((used - cpuAt.used) / (wall - cpuAt.wall) * 100)
    }

    private static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : 0
    }

    /// A display link holds its target strongly, so the ticker holds the counter weakly. Otherwise
    /// the counter and the link would keep each other alive.
    @MainActor
    private final class Ticker: NSObject {
        weak var counter: FrameCounter?
        init(_ counter: FrameCounter) { self.counter = counter }
        @objc func tick(_ link: CADisplayLink) {
            counter?.frame(link)
        }
    }
}
