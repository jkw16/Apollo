// Run from the repository root: swift scripts/make-icon.swift
import AppKit
import Foundation

let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 42, y: 42, width: 940, height: 940)
        let background = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
        NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.09, alpha: 1).setFill()
        background.fill()
        let orange = NSColor(calibratedRed: 1, green: 0.43, blue: 0.24, alpha: 1)
        let ring = NSBezierPath(ovalIn: CGRect(x: 230, y: 230, width: 564, height: 564))
        ring.lineWidth = 16; orange.setStroke(); ring.stroke()
        let sun = NSBezierPath(ovalIn: CGRect(x: 314, y: 314, width: 396, height: 396))
        let gradient = NSGradient(starting: NSColor(calibratedRed: 1, green: 0.75, blue: 0.40, alpha: 1), ending: orange)!
        gradient.draw(in: sun, angle: -45)
        for index in 0..<12 {
            let angle = Double(index) * Double.pi / 6
            let ray = NSBezierPath()
            ray.move(to: CGPoint(x: 512 + cos(angle) * 340, y: 512 + sin(angle) * 340))
            ray.line(to: CGPoint(x: 512 + cos(angle) * 385, y: 512 + sin(angle) * 385))
            ray.lineWidth = 16; ray.lineCapStyle = .round; ray.stroke()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
