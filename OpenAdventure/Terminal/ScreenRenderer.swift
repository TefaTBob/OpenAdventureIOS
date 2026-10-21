import CoreGraphics
import Foundation

/// Renders rows of text into a grayscale bitmap, 7×8 pixels per character
/// like the real machine (40 columns = 280 pixels wide). The number of rows
/// follows the monitor's shape.
/// The CRT shader later scales, colors and distresses it.
enum ScreenRenderer {
    struct Frame {
        var rows: [String]           // one entry per screen row
        var columns: Int             // 32, 40 or 80
        var cursor: (row: Int, column: Int)?
    }

    static func image(for frame: Frame) -> CGImage? {
        let cw = PixelFont.cellWidth, ch = PixelFont.cellHeight
        let width = frame.columns * cw
        let rowCount = max(1, frame.rows.count)
        let height = rowCount * ch
        var pixels = [UInt8](repeating: 0, count: width * height)

        for (r, row) in frame.rows.enumerated() {
            for (c, char) in row.prefix(frame.columns).enumerated() where char != " " {
                let glyph = PixelFont.glyph(for: char)
                let x0 = c * cw + 1, y0 = r * ch
                for gy in 0..<ch {
                    let bits = glyph[gy]
                    if bits == 0 { continue }
                    let base = (y0 + gy) * width + x0
                    for gx in 0..<5 where bits & (1 << UInt8(4 - gx)) != 0 {
                        pixels[base + gx] = 255
                    }
                }
            }
        }

        if let cursor = frame.cursor, cursor.row < rowCount,
           cursor.column < frame.columns {
            // Solid block, like the machine's flashing cursor.
            let x0 = cursor.column * cw, y0 = cursor.row * ch
            for y in y0..<(y0 + ch - 1) {
                for x in x0..<(x0 + cw) {
                    pixels[y * width + x] = 255 - pixels[y * width + x]
                }
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
