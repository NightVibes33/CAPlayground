import UIKit

extension UIColor {
    convenience init?(caHex value: String?) {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let raw = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let red = CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? CGFloat(raw & 0xff) / 255 : 1
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
