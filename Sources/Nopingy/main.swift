import Foundation
import AppKit
import NopingyCore

// The bundle also doubles as a small CLI for automation and network verification.
if CommandLine.arguments.contains("--check-interface") {
    Task { @MainActor in
        do { try InterfaceChecks.run(); exit(0) }
        catch { print("Interface regression failed: \(error.localizedDescription)"); exit(1) }
    }
    dispatchMain()
} else if let index = CommandLine.arguments.firstIndex(of: "--probe"), CommandLine.arguments.indices.contains(index + 1) {
    let address = CommandLine.arguments[index + 1]
    Task {
        do {
            let target = try Target.parse(address)
            let result = try await ProbeEngine.probe(target, settings: Settings())
            print("\(result.status.rawValue)\t\(result.latency.map { String(format: "%.3f ms", $0) } ?? "—")\t\(result.detail)")
            exit(result.status == .up ? 0 : 1)
        } catch { print(error.localizedDescription); exit(2) }
    }
    dispatchMain()
} else {
    NopingyApplication.main()
}
