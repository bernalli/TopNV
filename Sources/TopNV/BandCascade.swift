import AppKit
import QuartzCore
import TopNVCore
import os

final class BandSliceWindow: OverlayWindow {
  init(frame: CGRect) {
    super.init(frame: frame, level: OverlayLevel.bar, isOpaque: true,
               behavior: OverlayBehavior.bar.subtracting(.transient).union(.stationary))
    alphaValue = 0
    orderFrontRegardless()
  }
}

/// Each pair shares an opacity proportional to the part of its width reached by the entrance.
@MainActor
final class BandCascade {
  private struct Pair {
    let left: BandSliceWindow
    let right: BandSliceWindow
    let slice: BandSlice
    var alpha: CGFloat = 0
  }

  let frame: CGRect
  private let display: UInt32
  private var pairs: [Pair] = []
  private(set) var isRunning = false
  private static let logger = Logger(subsystem: "TopNV", category: "DesktopReturn")

  init(frame: CGRect, display: UInt32) {
    self.frame = frame
    self.display = display
    pairs = BandSlice.pairs(in: frame).map { slice in
      Pair(left: BandSliceWindow(frame: slice.left), right: BandSliceWindow(frame: slice.right), slice: slice)
    }
  }

  func apply(_ mask: BarMask) {
    let radius: CGFloat
    switch mask {
    case .none:
      guard isRunning else { return }
      radius = 0
      isRunning = false
    case let .rect(rect):
      if !isRunning { record("start") }
      isRunning = true
      radius = rect.width / 2
    }
    var lit = 0
    var outerAlpha: CGFloat = 0
    for index in pairs.indices {
      let pair = pairs[index]
      let alpha = pair.slice.opacity(radius: radius)
      if alpha > 0 {
        lit += 2
        outerAlpha = alpha
      }
      if pair.alpha != alpha {
        pair.left.alphaValue = alpha
        pair.right.alphaValue = alpha
        pairs[index].alpha = alpha
      }
    }
    record(isRunning ? "tick lit=\(lit) outerAlpha=\(outerAlpha)" : "end")
  }

  func close() {
    apply(.none)
    for pair in pairs {
      pair.left.close()
      pair.right.close()
    }
  }

  private func record(_ event: String) {
    let line = "display=\(display) cascade=\(event) atMS=\(Int(CACurrentMediaTime() * 1000))"
    Self.logger.info("\(line, privacy: .public)")
  }
}
