import AppKit
import Darwin
import Foundation
import TopNVCore

/// Opened only when the test copy installs its shortcuts.
final class SkyLightSpaces {
  private enum LoadError: Error { case unavailable, missingSymbol(String), noConnection }
  private typealias MainConnection = @convention(c) () -> Int32
  private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
  private typealias SetSpace = @convention(c) (Int32, CFString, UInt64) -> Void

  private let handle: UnsafeMutableRawPointer
  private let connection: Int32
  private let copySpaces: CopySpaces
  private let setSpace: SetSpace

  init() throws {
    let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let handle = dlopen(path, RTLD_LOCAL | RTLD_LAZY) else { throw LoadError.unavailable }
    do {
      let main: MainConnection = try Self.resolve(handle, "SLSMainConnectionID")
      copySpaces = try Self.resolve(handle, "SLSCopyManagedDisplaySpaces")
      setSpace = try Self.resolve(handle, "SLSManagedDisplaySetCurrentSpace")
      connection = main()
      guard connection != 0 else { throw LoadError.noConnection }
    } catch {
      dlclose(handle)
      throw error
    }
    self.handle = handle
  }

  deinit { dlclose(handle) }

  private static func resolve<Function>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> Function {
    guard let address = dlsym(handle, name) else { throw LoadError.missingSymbol(name) }
    return unsafeBitCast(address, to: Function.self)
  }

  func snapshot() throws -> ManagedDisplaySpaces {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(),
          let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
      throw ManagedDisplaySpaces.InventoryError.missingDisplay
    }
    return try ManagedDisplaySpaces(displays, mainUUID: CFUUIDCreateString(nil, uuid) as String)
  }

  func switchSpace(display: String, to target: UInt64) {
    setSpace(connection, display as CFString, target)
  }
}
