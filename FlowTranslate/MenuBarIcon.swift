import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            NSGradient(colors: [
                NSColor(calibratedRed: 0.05, green: 0.78, blue: 0.98, alpha: 1),
                NSColor(calibratedRed: 0.50, green: 0.31, blue: 1.0, alpha: 1)
            ])?.draw(in: background, angle: -35)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: "T", attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 - 0.5))
            return true
        }
        image.isTemplate = false
        return image
    }()
}
