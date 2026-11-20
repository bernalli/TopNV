/// Presentation changes for the notch band, decided from one sample per display.
public struct BandEntrance {
  public enum Sample { case desktop, revealed, unavailable }
  public enum Event { case settings, system, sample }
  public enum Action { case start, restore }

  private var previous: [UInt32: Sample] = [:]
  private var wasEnabled = false

  public init() {}

  public mutating func update(_ event: Event, enabled: Bool, samples: [UInt32: Sample],
                              reduceMotion: Bool) -> [UInt32: Action] {
    let activating = event == .settings && enabled && !wasEnabled
    wasEnabled = enabled
    var next: [UInt32: Sample] = [:]
    var actions: [UInt32: Action] = [:]
    for id in previous.keys where !enabled || samples[id] == nil { actions[id] = .restore }
    if enabled {
      for (id, sample) in samples {
        // A reveal straddling a Space switch or an unreadable sample cannot prove a return.
        let interrupted = event == .system || previous[id] == .unavailable
        next[id] = sample == .revealed && interrupted ? .unavailable : sample
        if event == .system || sample != .desktop || reduceMotion {
          actions[id] = .restore
        } else if activating || previous[id] == .revealed {
          actions[id] = .start
        }
      }
    }
    previous = next
    return actions
  }
}

extension BandEntrance.Sample {
  public init(_ evidence: MenuBarEvidence.Result) {
    guard evidence.permitsBandEntrance else { self = .unavailable; return }
    self = evidence.desktopRevealed ? .revealed : .desktop
  }
}
