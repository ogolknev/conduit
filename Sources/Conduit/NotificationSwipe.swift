import AppKit
import SwiftUI

struct NotificationSwipe: ViewModifier {
    let enabled: Bool
    let dismiss: () -> Void
    @State private var distance: CGFloat = 0
    @State private var width: CGFloat = 0
    private var threshold: CGFloat { min(140, max(65, width * 0.28)) }

    func body(content: Content) -> some View {
        swipeable(content)
            .transition(.asymmetric(insertion: .opacity,
                removal: .offset(x: distance < 0 ? -width : width).combined(with: .opacity)))
            .onChange(of: enabled) { value in if value { reset() } }
    }

    private func swipeable(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        let reveal = min(abs(distance), width)
        let progress = min(reveal / 56, 1)
        return content.clipShape(shape).offset(x: distance)
            .background {
                GeometryReader { geometry in
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(reveal >= threshold ? Palette.error : Palette.muted)
                        .scaleEffect(0.75 + 0.25 * progress)
                        .opacity(progress)
                        .position(x: distance > 0 ? reveal / 2 : geometry.size.width - reveal / 2,
                                  y: geometry.size.height / 2)
                }.background(Palette.canvas).allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipShape(shape)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { width = $0 }
            })
            .contentShape(shape)
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    guard enabled else { return }
                    if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                        distance = value.translation.width
                    } else { distance = 0 }
                }
                .onEnded { value in
                    guard enabled else { return }
                    distance = abs(value.translation.width) > abs(value.translation.height) * 1.4 ? value.translation.width : 0
                    finish()
                })
            .background {
                TrackpadSwipe(enabled: enabled, onChange: { distance = $0 }, onEnd: { cancelled in
                    if cancelled { reset() } else { finish() }
                })
            }
    }

    private func finish() {
        guard enabled else { return }
        guard abs(distance) >= threshold else { reset(); return }
        dismiss()
    }

    private func reset() {
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) { distance = 0 }
    }
}

// AppKit sends two-finger gestures as phased scroll events. Install a monitor
// only while the pointer is over this row and leave vertical scrolling to its parent.
private struct TrackpadSwipe: NSViewRepresentable {
    let enabled: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (Bool) -> Void
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.handler = self }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var handler: TrackpadSwipe?
        private var monitor: Any?
        private var tracking: NSTrackingArea?
        private var dx: CGFloat = 0
        private var dy: CGFloat = 0
        private var horizontal: Bool?
        private var inside = false
        private var beganHere = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func mouseEntered(with event: NSEvent) {
            inside = true
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }
        override func mouseExited(with event: NSEvent) {
            inside = false
            if horizontal != true { stop() }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            beganHere = false
            horizontal = nil
        }
        private func handle(_ event: NSEvent) -> Bool {
            guard handler?.enabled == true, event.window === window, event.hasPreciseScrollingDeltas, !event.phase.isEmpty,
                  event.momentumPhase.isEmpty else { return false }
            if event.phase.contains(.began) {
                beganHere = bounds.contains(convert(event.locationInWindow, from: nil))
                dx = 0
                dy = 0
                horizontal = nil
            }
            guard beganHere else { return false }
            if event.phase.contains(.cancelled) || event.phase.contains(.ended) {
                beganHere = false
                let handled = horizontal == true
                if handled { handler?.onEnd(event.phase.contains(.cancelled)) }
                horizontal = nil
                if !inside { stop() }
                return handled
            }
            dx += event.scrollingDeltaX
            dy += event.scrollingDeltaY
            if horizontal == nil && max(abs(dx), abs(dy)) >= 5 { horizontal = abs(dx) > abs(dy) * 1.4 }
            if horizontal == true { handler?.onChange(dx); return true }
            return false
        }
    }
}
