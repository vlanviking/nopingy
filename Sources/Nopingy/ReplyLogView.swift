import AppKit
import SwiftUI
import NopingyCore

struct ReplyLogView: NSViewRepresentable {
    let samples: [Sample]
    let autoScroll: Bool
    let emptyMessage: String
    let downColor: NSColor
    let errorColor: NSColor

    func makeNSView(context: Context) -> ReplyLogScrollView { ReplyLogScrollView() }

    func updateNSView(_ scroll: ReplyLogScrollView, context: Context) {
        let text = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        if samples.isEmpty { text.append(NSAttributedString(string: emptyMessage, attributes: normal)) }
        for (index, sample) in samples.enumerated() {
            var time = normal; time[.foregroundColor] = NSColor.tertiaryLabelColor
            text.append(NSAttributedString(string: sample.date.formatted(.dateTime.hour().minute().second()) + "  ", attributes: time))
            var detail = normal
            if sample.result.status == .down { detail[.foregroundColor] = downColor }
            if sample.result.status == .error { detail[.foregroundColor] = errorColor }
            text.append(NSAttributedString(string: sample.result.detail + (index == samples.count - 1 ? "" : "\n"), attributes: detail))
        }
        scroll.followTail = autoScroll
        if !scroll.textView.attributedString().isEqual(to: text) {
            let selection = scroll.textView.selectedRange()
            scroll.textView.textStorage?.setAttributedString(text)
            if selection.location <= text.length {
                scroll.textView.setSelectedRange(NSRange(location: selection.location, length: min(selection.length, text.length - selection.location)))
            }
        }
        scroll.resizeDocumentAndFollow()
        scroll.needsLayout = true
    }
}

// Move only this log's clip view. SwiftUI scrollTo in nested scroll views can
// also scroll the ancestor grid, hiding the first row's host headers.
@MainActor final class ReplyLogScrollView: NSScrollView {
    let textView = NSTextView(frame: .zero)
    var followTail = true
    private var updatingLayout = false

    init() {
        super.init(frame: .zero)
        drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; hasHorizontalScroller = false; autohidesScrollers = true
        textView.isEditable = false; textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.minSize = .zero; textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        documentView = textView
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        resizeDocumentAndFollow()
    }

    func resizeDocumentAndFollow() {
        guard !updatingLayout, contentSize.width > 0, let container = textView.textContainer,
              let manager = textView.layoutManager else { return }
        updatingLayout = true; defer { updatingLayout = false }
        let width = contentSize.width
        if abs(textView.frame.width - width) > 0.5 { textView.setFrameSize(NSSize(width: width, height: max(contentSize.height, textView.frame.height))) }
        container.containerSize = NSSize(width: max(1, width - textView.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(contentSize.height, ceil(manager.usedRect(for: container).height) + textView.textContainerInset.height * 2)
        if abs(textView.frame.height - height) > 0.5 { textView.setFrameSize(NSSize(width: width, height: height)) }
        if followTail {
            contentView.scroll(to: NSPoint(x: 0, y: max(0, height - contentSize.height)))
            reflectScrolledClipView(contentView)
        }
    }
}
