import AppKit
import SwiftUI

extension View {
    func porterOverlayScrollIndicators() -> some View {
        background(PorterOverlayScrollIndicatorConfigurator())
    }
}

private struct PorterOverlayScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PorterOverlayScrollIndicatorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PorterOverlayScrollIndicatorView)?.configureEnclosingScrollView()
    }
}

private final class PorterOverlayScrollIndicatorView: NSView {
    private var didScheduleRetry = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        guard let scrollView = enclosingScrollView() else {
            scheduleRetry()
            return
        }

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.knobStyle = .light
        scrollView.horizontalScroller?.knobStyle = .light
    }

    private func scheduleRetry() {
        guard !didScheduleRetry else { return }
        didScheduleRetry = true

        DispatchQueue.main.async { [weak self] in
            self?.didScheduleRetry = false
            self?.configureEnclosingScrollView()
        }
    }

    private func enclosingScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}
