// StatusItemController+Title: the status item's attributed title with the
// Pomodoro segment (spec_menubar.md §1.1).

import AppKit

extension StatusItemController {
    /// The menu bar font with monospaced digits.
    private static var titleFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    /// The elapsed time and project, then the Pomodoro glyph and countdown.
    static func title(_ content: StatusItemContent) -> NSAttributedString {
        let font = titleFont
        let title = NSMutableAttributedString(string: content.title, attributes: [.font: font])
        guard let pomodoro = content.pomodoro else {
            return title
        }
        if !content.title.isEmpty {
            title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }
        if let glyph = textGlyph(pomodoro.symbol, font: font) {
            title.append(NSAttributedString(attachment: glyph))
            title.append(NSAttributedString(string: "\u{2009}", attributes: [.font: font]))
        }
        title.append(NSAttributedString(string: pomodoro.text, attributes: [.font: font]))
        return title
    }

    /// A symbol as a text attachment, drawn at render time in the text
    /// color of the menu bar's appearance.
    private static func textGlyph(_ symbol: String, font: NSFont) -> NSTextAttachment? {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        guard let base = NSImage.symbol(symbol)?.withSymbolConfiguration(configuration)
        else {
            return nil
        }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
        return attachment
    }
}
