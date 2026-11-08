@MainActor
public protocol UpdaterControlling: AnyObject {
  var canCheckForUpdates: Bool { get }
  var automaticallyChecksForUpdates: Bool { get set }
  func start() throws
  func checkForUpdates()
}
