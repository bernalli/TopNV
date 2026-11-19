import Foundation
import TopNVBarCheck

let result = BarCheck.run(arguments: Array(CommandLine.arguments.dropFirst()), timeZone: .current)
if result.usage {
  FileHandle.standardError.write(Data((result.line + "\n").utf8))
} else {
  print(result.line)
}
exit(result.exitCode)
