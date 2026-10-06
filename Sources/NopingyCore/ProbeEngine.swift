import Foundation
import Network
import Darwin

public struct CommandOutput: Sendable {
    public let text: String
    public let exitCode: Int32
    public let timedOut: Bool
    public init(text: String, exitCode: Int32, timedOut: Bool) { self.text = text; self.exitCode = exitCode; self.timedOut = timedOut }
}

// Every process has a deadline and is terminated when its owning task is cancelled.
// Arguments go directly to Process; no target or alias is evaluated by a shell.
private final class CommandJob: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var expired = false

    func stop(deadline: Bool = false) {
        lock.lock()
        if deadline { expired = true } else { cancelled = true }
        let running = process
        lock.unlock()
        guard let running, running.isRunning else { return }
        running.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if running.isRunning { kill(running.processIdentifier, SIGKILL) }
        }
    }

    func run(path: String, arguments: [String], timeout: Double) throws -> CommandOutput {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = pipe; task.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["LANG"] = "C"
        task.environment = environment
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = task
        do { try task.run(); lock.unlock() } catch { lock.unlock(); throw error }
        let deadline = DispatchWorkItem { [weak self] in self?.stop(deadline: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.1, timeout), execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        deadline.cancel()
        lock.lock(); let wasCancelled = cancelled; let wasExpired = expired; process = nil; lock.unlock()
        if wasCancelled { throw CancellationError() }
        return CommandOutput(text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                             exitCode: task.terminationStatus, timedOut: wasExpired)
    }
}

public enum CommandRunner {
    public static func run(path: String, arguments: [String], timeout: Double) async throws -> CommandOutput {
        let job = CommandJob()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try job.run(path: path, arguments: arguments, timeout: timeout)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { job.stop() })
    }
}

private final class TCPJob: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<ProbeResult, Error>?
    private var completed = false
    private var cancelled = false
    private var started: UInt64 = 0

    func finish(_ result: Result<ProbeResult, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let callback = continuation; continuation = nil
        let active = connection; connection = nil
        lock.unlock()
        active?.stateUpdateHandler = nil
        active?.cancel()
        callback?.resume(with: result)
    }

    func cancel() {
        lock.lock(); cancelled = true; let registered = continuation != nil; lock.unlock()
        if registered { finish(.failure(CancellationError())) }
    }

    func run(host: String, port: UInt16, timeout: Double) async throws -> ProbeResult {
        try await withCheckedThrowingContinuation { callback in
            let active = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            lock.lock()
            if cancelled { lock.unlock(); callback.resume(throwing: CancellationError()); return }
            continuation = callback; connection = active; started = DispatchTime.now().uptimeNanoseconds
            lock.unlock()
            active.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - self.started) / 1_000_000
                    self.finish(.success(ProbeResult(status: .up, latency: elapsed, detail: "Port \(port) open · \(String(format: "%.2f", elapsed)) ms")))
                case .failed(let error), .waiting(let error):
                    let status: ProbeStatus
                    if case .dns = error { status = .error } else { status = .down }
                    let message: String
                    if case .posix(let code) = error { message = String(cString: strerror(code.rawValue)) }
                    else { message = String(describing: error) }
                    self.finish(.success(ProbeResult(status: status, detail: "Port \(port): \(message)")))
                default: break
                }
            }
            active.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.success(ProbeResult(status: .down, detail: "Port \(port) timed out after \(timeout) s")))
            }
        }
    }
}

public enum ProbeEngine {
    public static func probe(_ target: Target, settings: Settings) async throws -> ProbeResult {
        switch target.kind {
        case .tcp:
            let job = TCPJob()
            return try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await job.run(host: target.host, port: target.port!, timeout: settings.timeout)
            }, onCancel: { job.cancel() })
        case .icmp:
            let arguments = pingArguments(target, settings: settings)
            let output = try await CommandRunner.run(path: target.isIPv6 ? "/sbin/ping6" : "/sbin/ping", arguments: arguments,
                                                     timeout: settings.timeout + 0.5)
            return parsePing(output)
        case .dns:
            return try await dns(target.host, timeout: settings.timeout)
        case .traceroute:
            let output = try await trace(target.host, timeout: 45)
            return ProbeResult(status: output.exitCode == 0 && !output.timedOut ? .up : .error,
                               detail: output.text + (output.timedOut ? "\nTraceroute stopped after 45 seconds." : ""))
        }
    }

    public static func pingArguments(_ target: Target, settings: Settings, count: Int = 1, interval: Double? = nil) -> [String] {
        var args = ["-n", "-c", String(count), "-s", String(settings.packetSize)]
        if target.isIPv6 { args += ["-h", String(settings.ttl)] }
        else { args += ["-W", String(Int(settings.timeout * 1000)), "-t", String(Int(ceil(settings.timeout + Double(count) * (interval ?? 0)))), "-m", String(settings.ttl)] }
        if let interval { args += ["-i", String(interval)] }
        return args + [target.host]
    }

    public static func parsePing(_ output: CommandOutput) -> ProbeResult {
        let pattern = #"time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output.text, range: NSRange(output.text.startIndex..., in: output.text)),
           let range = Range(match.range(at: 1), in: output.text), let latency = Double(output.text[range]) {
            let line = output.text.components(separatedBy: .newlines).first(where: { $0.contains("time=") || $0.contains("time<") }) ?? "Reply received"
            return ProbeResult(status: .up, latency: latency, detail: line)
        }
        let lower = output.text.lowercased()
        let errors = ["unknown host", "cannot resolve", "operation not permitted", "permission denied", "invalid", "usage:", "nodename nor servname", "no route", "network is unreachable", "socket:"]
        if errors.contains(where: lower.contains) {
            let detail = output.text.components(separatedBy: .newlines).first(where: { line in
                errors.contains(where: line.lowercased().contains)
            }) ?? output.text
            return ProbeResult(status: .error, detail: detail)
        }
        return ProbeResult(status: .down, detail: "No reply before timeout")
    }

    public static func dns(_ host: String, timeout: Double) async throws -> ProbeResult {
        let start = DispatchTime.now().uptimeNanoseconds
        let seconds = String(max(1, Int(ceil(timeout))))
        let options = ["+short", "+time=\(seconds)", "+tries=1"]
        var ipv4 = in_addr(); var ipv6 = in6_addr()
        let isIP = host.withCString { inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1 }
        let text: String
        if isIP {
            let output = try await CommandRunner.run(path: "/usr/bin/dig", arguments: options + ["-x", host], timeout: timeout + 0.5)
            guard output.exitCode == 0 && !output.timedOut else { return ProbeResult(status: .error, detail: output.text.isEmpty ? "DNS lookup timed out" : output.text) }
            text = output.text
        } else {
            async let a = CommandRunner.run(path: "/usr/bin/dig", arguments: options + [host, "A"], timeout: timeout + 0.5)
            async let aaaa = CommandRunner.run(path: "/usr/bin/dig", arguments: options + [host, "AAAA"], timeout: timeout + 0.5)
            let outputs = try await [a, aaaa]
            guard outputs.allSatisfy({ $0.exitCode == 0 && !$0.timedOut }) else {
                let detail = outputs.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
                return ProbeResult(status: .error, detail: detail.isEmpty ? "DNS lookup timed out" : detail)
            }
            text = outputs.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard !text.isEmpty else { return ProbeResult(status: .error, detail: "No DNS records returned for \(host)") }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return ProbeResult(status: .up, latency: elapsed, detail: text)
    }

    public static func trace(_ host: String, timeout: Double = 45) async throws -> CommandOutput {
        let target = try Target.parse(host)
        return try await CommandRunner.run(path: target.isIPv6 ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute",
                                          arguments: ["-n", "-m", "30", "-q", "1", "-w", "1", target.host], timeout: timeout)
    }

    public static func burst(_ host: String, settings: Settings, count: Int, interval: Double) async throws -> CommandOutput {
        let target = try Target.parse(host)
        let count = min(1000, max(1, count)); let interval = min(10, max(0.2, interval))
        return try await CommandRunner.run(path: target.isIPv6 ? "/sbin/ping6" : "/sbin/ping",
                                          arguments: pingArguments(target, settings: settings, count: count, interval: interval),
                                          timeout: Double(count) * interval + settings.timeout + 2)
    }
}
