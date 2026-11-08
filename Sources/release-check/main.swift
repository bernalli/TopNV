import Foundation
import TopNVReleaseCheck

do { try ReleaseArguments(Array(CommandLine.arguments.dropFirst())).run() }
catch let violation as ReleaseViolation {
  FileHandle.standardError.write(Data("\(violation)\n".utf8)); exit(1)
} catch {
  FileHandle.standardError.write(Data("CLI: unable to read or validate release inputs\n".utf8)); exit(1)
}
