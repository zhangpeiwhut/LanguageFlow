import SwiftUI
import NaturalLanguage
import UIKit

struct InteractiveWordText: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var onLookup: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = DynamicTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.isUserInteractionEnabled = true
        textView.delegate = context.coordinator
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        textView.addGestureRecognizer(longPress)
        context.coordinator.textView = textView
        textView.attributedText = makeAttributedText()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.attributedText.string != text {
            uiView.attributedText = makeAttributedText()
            uiView.invalidateIntrinsicContentSize()
        }
    }
}

extension InteractiveWordText {
    func makeAttributedText() -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: fullRange)
        return attributed
    }

    final class DynamicTextView: UITextView {
        private var lastLayoutWidth: CGFloat = 0
        override var intrinsicContentSize: CGSize {
            guard frame.width > 0 else {
                return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
            }
            let size = sizeThatFits(CGSize(width: frame.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if abs(bounds.width - lastLayoutWidth) > 0.5 {
                lastLayoutWidth = bounds.width
                invalidateIntrinsicContentSize()
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UITextViewDelegate {
        var parent: InteractiveWordText
        weak var textView: UITextView?

        init(parent: InteractiveWordText) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let textView = textView else { return }
            let location = gesture.location(in: textView)
            guard let word = word(at: location, in: textView) else { return }
            presentDictionary(for: word)
        }

        private func word(at location: CGPoint, in textView: UITextView) -> String? {
            // 修正点击位置，考虑 inset
            var adjusted = location
            adjusted.x -= textView.textContainerInset.left
            adjusted.y -= textView.textContainerInset.top

            let layoutManager = textView.layoutManager
            let container = textView.textContainer
            let glyphIndex = layoutManager.glyphIndex(for: adjusted, in: container)

            // 确保点击在字形边界内
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
            if !glyphRect.contains(adjusted) {
                return nil
            }

            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard characterIndex < textView.textStorage.length else { return nil }

            let nsString = textView.textStorage.string as NSString
            let wordCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-"))

            var start = characterIndex
            var end = characterIndex

            while start > 0, let scalar = UnicodeScalar(nsString.character(at: start - 1)), wordCharacterSet.contains(scalar) {
                start -= 1
            }
            while end < nsString.length, let scalar = UnicodeScalar(nsString.character(at: end)), wordCharacterSet.contains(scalar) {
                end += 1
            }

            guard end > start else { return nil }
            return nsString.substring(with: NSRange(location: start, length: end - start))
        }

        private func presentDictionary(for term: String) {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            parent.onLookup(cleaned)
        }
    }
}
