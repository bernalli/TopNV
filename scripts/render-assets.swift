// render-assets.swift
//
// Renders every visual asset of TopNV with CoreGraphics, ImageIO and CoreText
// (no AppKit, no WindowServer). The app icon and the cover derive from
// AppIconMaster.png in the output directory; the menu bar icon is drawn directly.
// AppIcon.icon is the editable design source; the master is its full-canvas render.
//
// Usage:
//   swiftc -O scripts/render-assets.swift -o "$TMPDIR/render-assets"
//   "$TMPDIR/render-assets" Assets
//
// Output (relative to the output directory):
//   AppIcon.iconset/icon_{16,32,128,256,512}x{...}[@2x].png
//   AppIcon.icns                          (the iconset images, written with ImageIO)
//   MenuBarIcon.png, MenuBarIcon@2x.png   (template images, alpha only)
//   cover.png                             (2560x1280 README cover, design D at 2x)
//   social-preview.png                    (1280x640 GitHub social preview, same design)

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

enum RenderError: Error, CustomStringConvertible {
  case colorSpace
  case context(Int, Int)
  case image(String)
  case master(String)
  case destination(String)
  case write(String)

  var description: String {
    switch self {
    case .colorSpace: return "cannot create the sRGB color space"
    case .context(let w, let h): return "cannot create a \(w)x\(h) bitmap context"
    case .image(let name): return "cannot create the image for \(name)"
    case .master(let path):
      return
        "cannot load app icon master at \(path); provide AppIconMaster.png in the output directory"
    case .destination(let path): return "cannot create an image destination at \(path)"
    case .write(let path): return "cannot write \(path)"
    }
  }
}

// MARK: - Basics

guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else {
  FileHandle.standardError.write(Data("error: \(RenderError.colorSpace)\n".utf8))
  exit(1)
}

/// Builds an sRGB color from a 0xRRGGBB value and an alpha.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  let r = CGFloat((hex >> 16) & 0xFF) / 255
  let g = CGFloat((hex >> 8) & 0xFF) / 255
  let b = CGFloat(hex & 0xFF) / 255
  return CGColor(colorSpace: srgb, components: [r, g, b, alpha]) ?? CGColor(gray: 0, alpha: alpha)
}

/// Creates a transparent premultiplied RGBA bitmap context.
func makeContext(width: Int, height: Int) throws -> CGContext {
  guard
    let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { throw RenderError.context(width, height) }
  ctx.setShouldAntialias(true)
  ctx.setAllowsAntialiasing(true)
  ctx.interpolationQuality = .high
  return ctx
}

/// Flips a context so that the origin is top-left and y grows downward.
func flipToTopLeft(_ ctx: CGContext, height: Int) {
  ctx.translateBy(x: 0, y: CGFloat(height))
  ctx.scaleBy(x: 1, y: -1)
}

/// Writes an image as PNG, tagging the pixel density (72 dpi = 1x, 144 dpi = 2x).
func writePNG(_ image: CGImage, to url: URL, dpi: Int = 72) throws {
  guard
    let dest = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw RenderError.destination(url.path)
  }
  let props: [CFString: Any] = [
    kCGImagePropertyDPIWidth: dpi,
    kCGImagePropertyDPIHeight: dpi,
  ]
  CGImageDestinationAddImage(dest, image, props as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { throw RenderError.write(url.path) }
}

/// Writes an image as a PNG without metadata, for the pictures published on GitHub: it keeps
/// the critical chunks (IHDR, IDAT, IEND) and sRGB, and drops every other ancillary chunk
/// (eXIf, pHYs, text, time).
func writeBarePNG(_ image: CGImage, to url: URL) throws {
  let encoded = NSMutableData()
  guard
    let dest = CGImageDestinationCreateWithData(
      encoded as CFMutableData, UTType.png.identifier as CFString, 1, nil)
  else {
    throw RenderError.destination(url.path)
  }
  CGImageDestinationAddImage(dest, image, nil)
  guard CGImageDestinationFinalize(dest) else { throw RenderError.write(url.path) }
  let bytes = [UInt8](encoded as Data)
  let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  guard bytes.count >= signature.count, Array(bytes[0..<signature.count]) == signature else {
    throw RenderError.write(url.path)
  }
  var bare = signature
  var offset = signature.count
  var ended = false
  while offset < bytes.count {
    guard !ended, offset + 12 <= bytes.count else { throw RenderError.write(url.path) }
    let length =
      Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8
      | Int(bytes[offset + 3])
    let end = offset + 12 + length
    guard end <= bytes.count else { throw RenderError.write(url.path) }
    let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
    // A chunk is critical when the first letter of its type is upper case.
    if type.first?.isUppercase == true || type == "sRGB" {
      bare += bytes[offset..<end]
    }
    ended = type == "IEND"
    offset = end
  }
  guard ended else { throw RenderError.write(url.path) }
  guard (try? Data(bare).write(to: url)) != nil else { throw RenderError.write(url.path) }
}

// MARK: - App icon

/// Loads the full-canvas Icon Composer render before writing any output.
func loadMaster(from url: URL) throws -> CGImage {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw RenderError.master(url.path) }
  return image
}

/// Geometry of the app icon in the 1024x1024 y-down design space.
enum IconGrid {
  /// Body: macOS grid, 824x824 centred on the 1024 canvas.
  static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
}

/// Scales the master into the macOS body, preserving its outline and drop shadow.
func drawIcon(_ ctx: CGContext, scale s: CGFloat, master: CGImage) {
  ctx.saveGState()
  ctx.scaleBy(x: s, y: s)
  ctx.setShadow(
    offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.38))
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)

  // The context is y-down; draw the image in a y-up frame to keep it upright.
  ctx.translateBy(x: 0, y: 1024)
  ctx.scaleBy(x: 1, y: -1)
  ctx.draw(master, in: IconGrid.body)

  ctx.endTransparencyLayer()
  ctx.restoreGState()
}

func renderIcon(pixels: Int, master: CGImage) throws -> CGImage {
  let ctx = try makeContext(width: pixels, height: pixels)
  flipToTopLeft(ctx, height: pixels)
  drawIcon(ctx, scale: CGFloat(pixels) / 1024, master: master)
  guard let image = ctx.makeImage() else { throw RenderError.image("icon \(pixels)px") }
  return image
}

// MARK: - Menu bar icon

/// Black template with transparency on an 18x18 point canvas, opening bottom-right.
func renderMenuBarIcon(scale: Int) throws -> CGImage {
  let px = 18 * scale
  let ctx = try makeContext(width: px, height: px)
  flipToTopLeft(ctx, height: px)
  ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

  // At 1x, 3 pt puts the straight stroke edges and cap extrema on whole pixels.
  // At 2x, 3.5 pt is exactly 7 pixels. Both retain the same 10.5 pt outer radius.
  let stroke: CGFloat = scale == 1 ? 3 : 3.5
  ctx.setStrokeColor(color(0x000000))
  ctx.setLineWidth(stroke)
  ctx.setLineCap(.round)
  ctx.addArc(
    center: CGPoint(x: 13.5, y: 13.5), radius: 10.5 - stroke / 2,
    startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
  ctx.strokePath()

  guard let image = ctx.makeImage() else { throw RenderError.image("menu bar icon @\(scale)x") }
  return image
}

// MARK: - Cover

/// Geometry and copy of cover design D (1280x640 CSS px, y-down). The PNGs render it at a scale.
enum CoverDesign {
  static let size = CGSize(width: 1280, height: 640)
  static let menuBarHeight: CGFloat = 56
  static let menuBarPadding: CGFloat = 30
  static let menuFontSize: CGFloat = 19
  static let menuGap: CGFloat = 28
  static let statusGap: CGFloat = 24
  static let menuItems = ["Finder", "File", "Edit", "View", "Go", "Window", "Help"]
  static let clock = "Sat 15 Nov 10:42"
  static let screenRadius: CGFloat = 34
  static let screenColor: UInt32 = 0xF2F2F4
  static let inkColor: UInt32 = 0x111111
  static let contentInset: CGFloat = 96
  static let iconColumn: CGFloat = 330
  static let columnGap: CGFloat = 64
  static let iconSide: CGFloat = 350
  static let iconMarginLeft: CGFloat = -18
  static let title = "TopNV"
  static let tagline = [
    "The notch disappears into a black menu bar.", "The screen gets rounded corners.",
  ]
  static let footnote = "Free and open source \u{00B7} macOS 14 or later"
}

/// CSS font weights mapped to CoreText weight traits of the system font (SF Pro).
enum FontWeight {
  static let regular: CGFloat = 0  // 400
  static let medium: CGFloat = 0.23  // 500
  static let semibold: CGFloat = 0.3  // 600
  static let bold: CGFloat = 0.4  // 700
  static let heavy: CGFloat = 0.56  // 800
}

/// Returns the system font (SF Pro) at `size` with a weight trait; falls back to Helvetica Neue.
func systemFont(size: CGFloat, weight: CGFloat) -> CTFont {
  guard let base = CTFontCreateUIFontForLanguage(.system, size, nil) else {
    return CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
  }
  let attrs: [CFString: Any] = [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]]
  let descriptor = CTFontDescriptorCreateCopyWithAttributes(
    CTFontCopyFontDescriptor(base), attrs as CFDictionary)
  return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func makeLine(_ text: String, font: CTFont, color fg: CGColor, kern: CGFloat = 0) -> CTLine {
  let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: fg,
    kCTKernAttributeName: kern,
  ]
  let string = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
  return CTLineCreateWithAttributedString(string)
}

func lineWidth(_ line: CTLine) -> CGFloat {
  CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Offset from the top of a CSS line box of height `lineHeight` to the baseline of `font`.
func baselineOffset(_ font: CTFont, lineHeight: CGFloat) -> CGFloat {
  let ascent = CTFontGetAscent(font)
  let content = ascent + CTFontGetDescent(font)
  return (lineHeight - content) / 2 + ascent
}

/// CSS `line-height: normal` of `font`.
func normalLineHeight(_ font: CTFont) -> CGFloat {
  CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
}

/// Draws a line with its baseline at `origin` in a y-down context whose text matrix is flipped.
func drawLine(_ ctx: CGContext, _ line: CTLine, at origin: CGPoint) {
  ctx.textPosition = origin
  CTLineDraw(line, ctx)
}

/// Draws an image upright into `rect` of a y-down context.
func drawImage(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
  ctx.saveGState()
  ctx.translateBy(x: rect.minX, y: rect.maxY)
  ctx.scaleBy(x: 1, y: -1)
  ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
  ctx.restoreGState()
}

/// Renders cover design D: a black macOS menu bar over a light screen with four rounded corners.
/// `icon` is the 1024px app icon (AppIcon.iconset/icon_512x512@2x.png); the menu bar shows the
/// MenuBarIcon template at the same scale. `scale` 2 gives 2560x1280.
func renderCover(icon: CGImage, scale: Int) throws -> CGImage {
  typealias D = CoverDesign
  let s = CGFloat(scale)
  let width = Int(D.size.width) * scale
  let height = Int(D.size.height) * scale
  let ctx = try makeContext(width: width, height: height)
  flipToTopLeft(ctx, height: height)
  ctx.scaleBy(x: s, y: s)
  ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)  // upright glyphs in the y-down space

  let W = D.size.width
  let H = D.size.height
  ctx.setFillColor(color(0x000000))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

  // Menu bar: Finder menus on the left; TopNV's menu bar icon, battery and clock on the right.
  let barMid = D.menuBarHeight / 2
  let white = color(0xFFFFFF)
  let menuRegular = systemFont(size: D.menuFontSize, weight: FontWeight.regular)
  let menuBold = systemFont(size: D.menuFontSize, weight: FontWeight.bold)
  func menuBaseline(_ font: CTFont) -> CGFloat {
    barMid - normalLineHeight(font) / 2 + baselineOffset(font, lineHeight: normalLineHeight(font))
  }
  var x = D.menuBarPadding
  for (index, item) in D.menuItems.enumerated() {
    let font = index == 0 ? menuBold : menuRegular
    let line = makeLine(item, font: font, color: white)
    drawLine(ctx, line, at: CGPoint(x: x, y: menuBaseline(font)))
    x += lineWidth(line) + D.menuGap
  }

  let clock = makeLine(D.clock, font: menuRegular, color: white)
  let clockX = W - D.menuBarPadding - lineWidth(clock)
  drawLine(ctx, clock, at: CGPoint(x: clockX, y: menuBaseline(menuRegular)))

  let battery = CGRect(x: clockX - D.statusGap - 28, y: barMid - 7, width: 28, height: 14)
  ctx.setStrokeColor(white)
  ctx.setLineWidth(2)
  ctx.addPath(
    CGPath(
      roundedRect: battery.insetBy(dx: 1, dy: 1), cornerWidth: 3, cornerHeight: 3, transform: nil))
  ctx.strokePath()

  // TopNV's own menu bar template (MenuBarIcon.png / @2x), 18 pt, filled white like the text.
  let statusIconSide: CGFloat = 18
  let template = try renderMenuBarIcon(scale: scale)
  let statusRect = CGRect(
    x: battery.minX - D.statusGap - statusIconSide, y: barMid - statusIconSide / 2,
    width: statusIconSide, height: statusIconSide)
  ctx.saveGState()
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)
  drawImage(ctx, template, in: statusRect)
  ctx.setBlendMode(.sourceIn)  // keep the template's alpha, replace its colour
  ctx.setFillColor(white)
  ctx.fill(statusRect)
  ctx.endTransparencyLayer()
  ctx.restoreGState()

  // Screen: light panel under the bar, all four corners rounded.
  let screen = CGRect(x: 0, y: D.menuBarHeight, width: W, height: H - D.menuBarHeight)
  ctx.setFillColor(color(D.screenColor))
  ctx.addPath(
    CGPath(
      roundedRect: screen, cornerWidth: D.screenRadius, cornerHeight: D.screenRadius,
      transform: nil))
  ctx.fillPath()

  // App icon, vertically centred, with drop-shadow(0 26px 36px rgba(0,0,0,0.18)).
  let iconRect = CGRect(
    x: D.contentInset + D.iconMarginLeft, y: screen.midY - D.iconSide / 2,
    width: D.iconSide, height: D.iconSide)
  ctx.saveGState()
  // Shadow parameters live in device space (y-up, unscaled).
  ctx.setShadow(offset: CGSize(width: 0, height: -26 * s), blur: 36 * s, color: color(0, 0.18))
  drawImage(ctx, icon, in: iconRect)
  ctx.restoreGState()

  // Text column: title, two-line tagline, footnote; 22px gaps, vertically centred.
  let ink = color(D.inkColor)
  let textX = D.contentInset + D.iconColumn + D.columnGap
  let titleFont = systemFont(size: 136, weight: FontWeight.heavy)
  let tagFont = systemFont(size: 34, weight: FontWeight.semibold)
  let footFont = systemFont(size: 22, weight: FontWeight.medium)
  let titleLH: CGFloat = 136 * 0.9
  let tagLH: CGFloat = 34 * 1.25
  let footLH = normalLineHeight(footFont)
  let gap: CGFloat = 22
  let blockHeight = titleLH + gap + tagLH * CGFloat(D.tagline.count) + gap + footLH
  var top = screen.midY - blockHeight / 2

  drawLine(
    ctx, makeLine(D.title, font: titleFont, color: ink, kern: -5),
    at: CGPoint(x: textX, y: top + baselineOffset(titleFont, lineHeight: titleLH)))
  top += titleLH + gap
  for text in D.tagline {
    drawLine(
      ctx, makeLine(text, font: tagFont, color: ink),
      at: CGPoint(x: textX, y: top + baselineOffset(tagFont, lineHeight: tagLH)))
    top += tagLH
  }
  top += gap
  drawLine(
    ctx, makeLine(D.footnote, font: footFont, color: color(D.inkColor, 0.6)),
    at: CGPoint(x: textX, y: top + baselineOffset(footFont, lineHeight: footLH)))

  guard let image = ctx.makeImage() else { throw RenderError.image("cover @\(scale)x") }
  return image
}

// MARK: - Main

func run() throws {
  let args = CommandLine.arguments
  guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-assets <output-dir>\n".utf8))
    exit(2)
  }
  let out = URL(fileURLWithPath: args[1], isDirectory: true)
  let master = try loadMaster(from: out.appendingPathComponent("AppIconMaster.png"))
  let iconset = out.appendingPathComponent("AppIcon.iconset", isDirectory: true)
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

  var cache: [Int: CGImage] = [:]
  func icon(_ px: Int) throws -> CGImage {
    if let hit = cache[px] { return hit }
    let image = try renderIcon(pixels: px, master: master)
    cache[px] = image
    return image
  }

  let iconSizes = [16, 32, 128, 256, 512].flatMap { points in [1, 2].map { (points, $0) } }
  for (points, scale) in iconSizes {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try writePNG(
      try icon(points * scale), to: iconset.appendingPathComponent(name), dpi: 72 * scale)
    print("wrote AppIcon.iconset/\(name) (\(points * scale)px)")
  }

  // iconutil is not always usable, so the .icns is written directly with ImageIO.
  let icnsURL = out.appendingPathComponent("AppIcon.icns")
  guard
    let icns = CGImageDestinationCreateWithURL(
      icnsURL as CFURL, "com.apple.icns" as CFString, iconSizes.count, nil)
  else {
    throw RenderError.destination(icnsURL.path)
  }
  for (points, scale) in iconSizes {
    let dpi = 72 * scale
    let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(icns, try icon(points * scale), props as CFDictionary)
  }
  guard CGImageDestinationFinalize(icns) else { throw RenderError.write(icnsURL.path) }
  print("wrote AppIcon.icns (\(iconSizes.count) images)")

  try writePNG(
    try renderMenuBarIcon(scale: 1), to: out.appendingPathComponent("MenuBarIcon.png"), dpi: 72)
  try writePNG(
    try renderMenuBarIcon(scale: 2), to: out.appendingPathComponent("MenuBarIcon@2x.png"), dpi: 144)
  print("wrote MenuBarIcon.png (18px), MenuBarIcon@2x.png (36px)")

  // The cover uses the 1024px icon, the same image written as icon_512x512@2x.png.
  try writeBarePNG(
    try renderCover(icon: try icon(1024), scale: 2), to: out.appendingPathComponent("cover.png"))
  print("wrote cover.png (2560x1280, README cover)")
  try writeBarePNG(
    try renderCover(icon: try icon(1024), scale: 1),
    to: out.appendingPathComponent("social-preview.png"))
  print("wrote social-preview.png (1280x640, GitHub social preview)")
}

do {
  try run()
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
