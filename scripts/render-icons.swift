#!/usr/bin/env swift
// Renders the VZenit app icon at all required sizes with TRANSPARENT corners.
// Mirrors design/icon-1-envelope-z.svg exactly — kept in code so we don't
// depend on rsvg-convert/inkscape and so qlmanage's white-flatten can't bite us.

import AppKit
import CoreGraphics

// Geometry from the SVG (1024×1024 reference frame).
let canvas: CGFloat = 1024
let bgColor   = CGColor(red: 0x0e/255.0, green: 0x16/255.0, blue: 0x22/255.0, alpha: 1)
let fgColor   = CGColor(red: 0x4a/255.0, green: 0xd8/255.0, blue: 0xb0/255.0, alpha: 1)
let cornerR: CGFloat = 224

struct Bar  { let x, y, w, h, r: CGFloat }
struct Dot  { let cx, cy, r: CGFloat }
struct Seg  { let x1, y1, x2, y2, w: CGFloat }

let bars = [
    Bar(x: 160, y: 232, w: 704, h: 56, r: 8),
    Bar(x: 160, y: 736, w: 704, h: 56, r: 8),
]
let sustain = Seg(x1: 500, y1: 488, x2: 600, y2: 488, w: 14)
let dots: [Dot] = [
    Dot(cx: 760, cy: 368, r: 22),
    Dot(cx: 680, cy: 428, r: 22),
    Dot(cx: 600, cy: 488, r: 22),
    Dot(cx: 500, cy: 488, r: 22),
    Dot(cx: 408, cy: 552, r: 22),
    Dot(cx: 320, cy: 612, r: 22),
    Dot(cx: 232, cy: 672, r: 22),
]

func render(size: Int, to url: URL) throws {
    let scale = CGFloat(size) / canvas
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext create failed") }

    // SVG y-down → CG y-up: flip so the SVG coords map correctly.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)

    // Rounded background — anything outside this path stays transparent.
    let bgRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
    ctx.addPath(bgPath); ctx.setFillColor(bgColor); ctx.fillPath()

    ctx.setFillColor(fgColor)
    for b in bars {
        let r = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: b.r, cornerHeight: b.r, transform: nil))
        ctx.fillPath()
    }
    for d in dots {
        let r = CGRect(x: d.cx - d.r, y: d.cy - d.r, width: d.r*2, height: d.r*2)
        ctx.fillEllipse(in: r)
    }

    ctx.setStrokeColor(fgColor)
    ctx.setLineWidth(sustain.w)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: sustain.x1, y: sustain.y1))
    ctx.addLine(to: CGPoint(x: sustain.x2, y: sustain.y2))
    ctx.strokePath()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try png.write(to: url)
}

let outDir = URL(fileURLWithPath: "Sources/VZenit/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let url = outDir.appendingPathComponent("AppIcon-\(s).png")
    try render(size: s, to: url)
    print("wrote \(url.lastPathComponent)")
}
