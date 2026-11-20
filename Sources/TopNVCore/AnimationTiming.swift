/// CSS cubic-bezier curves use elapsed time as x and the interpolated value as y.
struct AnimationTiming {
  let firstX: Double
  let firstY: Double
  let secondX: Double
  let secondY: Double

  init(_ firstX: Double, _ firstY: Double, _ secondX: Double, _ secondY: Double) {
    self.firstX = firstX
    self.firstY = firstY
    self.secondX = secondX
    self.secondY = secondY
  }

  static let easeInOut = Self(0.42, 0, 0.58, 1)
  static let easeOut = Self(0, 0, 0.58, 1)
  static let linear = Self(0, 0, 1, 1)
  static let arrow = Self(0.3, 0, 0.2, 1)
  static let calm = Self(0.65, 0, 0.35, 1)
  static let settle = Self(0.16, 1, 0.3, 1)
  static let out = Self(0.2, 0.7, 0.2, 1)
  static let slow = Self(0.4, 0, 0.1, 1)

  func progress(_ time: Double, from start: Double = 0, to end: Double) -> Double {
    // A clock without a value stays at the start instead of reaching the geometry.
    if !(time > start) { return 0 }
    if time >= end { return 1 }
    let fraction = (time - start) / (end - start)
    if firstX == firstY && secondX == secondY { return fraction }
    func coordinate(_ parameter: Double, _ first: Double, _ second: Double) -> Double {
      let inverse = 1 - parameter
      return 3 * inverse * inverse * parameter * first
        + 3 * inverse * parameter * parameter * second + parameter * parameter * parameter
    }
    var low = 0.0
    var high = 1.0
    for _ in 0..<20 {
      let middle = (low + high) / 2
      if coordinate(middle, firstX, secondX) < fraction { low = middle } else { high = middle }
    }
    return coordinate((low + high) / 2, firstY, secondY)
  }
}
