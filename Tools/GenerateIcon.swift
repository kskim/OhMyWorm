#!/usr/bin/env swift
// Generates App/Assets.xcassets/AppIcon.appiconset from code.
// Run from the repo root: swift Tools/GenerateIcon.swift
// Classic-skin worm eyeing a snack on a warm cream tile.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: size * 4, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}

func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> CGColor {
    func ch(_ h: UInt32, _ s: UInt32) -> Double { Double((h >> s) & 0xFF) / 255 }
    return CGColor(red: ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t,
                   green: ch(a, 8) + (ch(b, 8) - ch(a, 8)) * t,
                   blue: ch(a, 0) + (ch(b, 0) - ch(a, 0)) * t, alpha: 1)
}

// Background: warm cream gradient + soft vignette.
let bg = CGGradient(colorsSpace: colorSpace, colors: [rgb(0xFFF9F0), rgb(0xFFE4C4)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])
let vig = CGGradient(colorsSpace: colorSpace, colors: [rgb(0xB47833, 0), rgb(0xB47833, 0.22)] as CFArray, locations: [0.55, 1])!
ctx.drawRadialGradient(vig, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: 750, options: [])

// Worm along a C arc, tail first so the head lands on top.
let center = CGPoint(x: 470, y: 500)
let radius = 290.0
let startAngle = 160.0 * Double.pi / 180
let sweep = 260.0 * Double.pi / 180
let segments = 26
var head = CGPoint.zero
for i in (0..<segments).reversed() {
    let t = Double(i) / Double(segments - 1)
    let theta = startAngle - sweep * t
    let p = CGPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
    let r = 100.0 + (42.0 - 100.0) * t
    if i == 0 { head = p }
    ctx.setFillColor(lerp(0x58B368, 0xB7E4A8, t))
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(rgb(0xFFFFFF, 0.35))
    let g = r * 0.22
    ctx.fillEllipse(in: CGRect(x: p.x - r * 0.3 - g, y: p.y + r * 0.3 - g, width: g * 2, height: g * 2))
}

// Face: eyes looking toward the apple.
let apple = CGPoint(x: 800, y: 210)
let forward = CGVector(dx: -sin(startAngle), dy: cos(startAngle))
let side = CGVector(dx: -forward.dy, dy: forward.dx)
for sign in [-1.0, 1.0] {
    let eye = CGPoint(x: head.x + forward.dx * 55 + side.dx * 38 * sign,
                      y: head.y + forward.dy * 55 + side.dy * 38 * sign)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: eye.x - 34, y: eye.y - 34, width: 68, height: 68))
    var look = CGVector(dx: apple.x - eye.x, dy: apple.y - eye.y)
    let len = max((look.dx * look.dx + look.dy * look.dy).squareRoot(), 0.001)
    look.dx /= len; look.dy /= len
    let pupil = CGPoint(x: eye.x + look.dx * 12, y: eye.y + look.dy * 12)
    ctx.setFillColor(rgb(0x222222))
    ctx.fillEllipse(in: CGRect(x: pupil.x - 15, y: pupil.y - 15, width: 30, height: 30))
}

// Apple snack.
ctx.setFillColor(rgb(0xE23B3B))
ctx.fillEllipse(in: CGRect(x: apple.x - 78, y: apple.y - 78, width: 156, height: 156))
ctx.setFillColor(rgb(0xFFFFFF, 0.4))
ctx.saveGState()
ctx.translateBy(x: apple.x - 30, y: apple.y + 28)
ctx.rotate(by: -0.5)
ctx.fillEllipse(in: CGRect(x: -12, y: -26, width: 24, height: 52))
ctx.restoreGState()
ctx.setFillColor(rgb(0x7A4A21))
ctx.saveGState()
ctx.translateBy(x: apple.x + 8, y: apple.y + 95)
ctx.rotate(by: 0.25)
ctx.fill(CGRect(x: -7, y: -25, width: 14, height: 50))
ctx.restoreGState()
ctx.setFillColor(rgb(0x58B368))
ctx.saveGState()
ctx.translateBy(x: apple.x + 42, y: apple.y + 108)
ctx.rotate(by: -0.5)
ctx.fillEllipse(in: CGRect(x: -32, y: -13, width: 64, height: 26))
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("no image") }

// Write 1024 master + scaled appiconset.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let setURL = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: setURL, withIntermediateDirectories: true)
func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("no dest \(url)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(url)") }
}
write(image, to: setURL.appendingPathComponent("icon_512x512@2x.png"))

let sizes = ["16x16", "16x16@2x", "32x32", "32x32@2x", "128x128", "128x128@2x", "256x256", "256x256@2x", "512x512"]
let pixels = [16, 32, 32, 64, 128, 256, 256, 512, 512]
for (name, px) in zip(sizes, pixels) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(px)", "\(px)",
                      setURL.appendingPathComponent("icon_512x512@2x.png").path,
                      "--out", setURL.appendingPathComponent("icon_\(name).png").path]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("sips failed \(name)") }
}

let contents = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try contents.write(to: setURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try """
{ "info" : { "version" : 1, "author" : "xcode" } }
""".write(to: setURL.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("appiconset written to \(setURL.path)")
