import AppKit
import SwiftUI

struct NotificationSwipe: ViewModifier {
    let enabled: Bool
    let dismiss: () -> Void
    @State private var distance: CGFloat = 0
    @State private var width: CGFloat = 0
    private var threshold: CGFloat { min(140, max(65, width * 0.28)) }

    func body(content: Content) -> some View {
        if enabled { swipeable(content) }
        else { content }
    }

    private func swipeable(_ content: Content) -> some View {
        content.offset(x: distance)
            .background {
                if distance != 0 {
                    HStack {
                        if distance < 0 { Spacer() }
                        Image(systemName: "xmark").accessibilityLabel(L("Удалить с телефона"))
                        if distance > 0 { Spacer() }
                    }.padding(.horizontal, 20).frame(maxHeight: .infinity)
                        .foregroundStyle(abs(distance) >= threshold ? Palette.error : Palette.muted)
                        .background(Palette.canvas)
                }
            }
            .clipped()
            .background(GeometryReader { geometry in
                Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { width = $0 }
            })
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                        distance = value.translation.width
                    } else { distance = 0 }
                }
                .onEnded { value in
                    distance = abs(value.translation.width) > abs(value.translation.height) * 1.4 ? value.translation.width : 0
                    finish()
                })
            .onDisappear { distance = 0 }
            .background {
                TrackpadSwipe(onChange: { distance = $0 }, onEnd: { cancelled in
                    if cancelled { withAnimation { distance = 0 } } else { finish() }
                })
            }
    }

    private func finish() {
        let shouldDismiss = abs(distance) >= threshold
        withAnimation(.easeOut(duration: 0.18)) { distance = 0 }
        if shouldDismiss { dismiss() }
    }
}

// AppKit sends two-finger gestures as phased scroll events. Install a monitor
// only while the pointer is over this row and leave vertical scrolling to its parent.
private struct TrackpadSwipe: NSViewRepresentable {
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
            guard event.window === window, event.hasPreciseScrollingDeltas, !event.phase.isEmpty,
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
