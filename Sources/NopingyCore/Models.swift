import Foundation
import Darwin

public enum ProbeKind: String, Codable, CaseIterable, Sendable {
    case icmp, tcp, dns, traceroute
    public var label: String { rawValue == "icmp" ? "ICMP" : rawValue == "tcp" ? "TCP" : rawValue == "dns" ? "DNS" : "TRACE" }
}

public struct Target: Codable, Equatable, Sendable {
    public let host: String
    public let port: UInt16?
    public let kind: ProbeKind
    public var isIPv6: Bool { host.contains(":") }
    public var address: String {
        if kind == .dns { return "D/\(host)" }
        if kind == .traceroute { return "T/\(host)" }
        guard let port else { return host }
        return isIPv6 ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    public static func parse(_ text: String) throws -> Target {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var kind: ProbeKind = .icmp
        if value.uppercased().hasPrefix("D/") { kind = .dns; value = String(value.dropFirst(2)) }
        if value.uppercased().hasPrefix("T/") { kind = .traceroute; value = String(value.dropFirst(2)) }
        var host = value
        var port: UInt16?
        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]") else { throw TargetError.invalid(text) }
            host = String(value[value.index(after: value.startIndex)..<end])
            let suffix = String(value[value.index(after: end)...])
            if !suffix.isEmpty {
                guard suffix.hasPrefix(":"), kind == .icmp,
                      let parsed = UInt16(suffix.dropFirst()), parsed > 0 else { throw TargetError.invalid(text) }
                port = parsed; kind = .tcp
            }
            guard host.contains(":") else { throw TargetError.invalid(text) }
        } else if value.filter({ $0 == ":" }).count == 1 {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard kind == .icmp, let parsed = UInt16(parts[1]), parsed > 0 else { throw TargetError.invalid(text) }
            host = String(parts[0]); port = parsed; kind = .tcp
        }
        guard isValidHost(host) else { throw TargetError.invalid(text) }
        return Target(host: host, port: port, kind: kind)
    }

    private static func isValidHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, !value.hasPrefix("-") else { return false }
        if value.contains(":") {
            let pieces = value.split(separator: "%", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { return false }
            if pieces.count == 2 {
                guard !pieces[1].isEmpty, pieces[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
            }
            var bytes = in6_addr()
            return String(pieces[0]).withCString { inet_pton(AF_INET6, $0, &bytes) == 1 }
        }
        let name = value.hasSuffix(".") ? String(value.dropLast()) : value
        return !name.isEmpty && name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }
}

public enum TargetError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let value): return "Invalid target: \(value). Use a hostname, IP address, host:port, or [IPv6]:port." }
    }
}

public struct HostDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var target: Target
    public var alias: String
    public init(id: UUID = UUID(), target: Target, alias: String = "") { self.id = id; self.target = target; self.alias = alias }
    public var name: String { alias.isEmpty ? target.host : alias }
    public var inputLine: String { alias.isEmpty ? target.address : "\(alias) = \(target.address)" }

    public static func parseList(_ text: String) throws -> [HostDefinition] {
        var result: [HostDefinition] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.components(separatedBy: "#")[0]
            for raw in line.components(separatedBy: ",") {
                let item = raw.trimmingCharacters(in: .whitespaces)
                if item.isEmpty { continue }
                let parts = item.components(separatedBy: "=")
                guard parts.count <= 2 else { throw TargetError.invalid(item) }
                let alias = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
                guard alias.count <= 100 else { throw TargetError.invalid(item) }
                result.append(HostDefinition(target: try Target.parse(parts.last!), alias: alias))
            }
        }
        guard result.count <= 128 else { throw TargetError.invalid("A maximum of 128 hosts can be added at once") }
        return result
    }
}

public enum ProbeStatus: String, Codable, CaseIterable, Sendable {
    case idle, checking, up, down, error
    public var label: String { rawValue.capitalized }
}

public struct ProbeResult: Sendable {
    public var status: ProbeStatus
    public var latency: Double?
    public var detail: String
    public init(status: ProbeStatus, latency: Double? = nil, detail: String) {
        self.status = status; self.latency = latency; self.detail = detail
    }
}

public struct Sample: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let result: ProbeResult
    public init(date: Date = Date(), result: ProbeResult) { self.date = date; self.result = result }
}

public struct ProbeStatistics: Sendable {
    public init() {}
    public private(set) var sent = 0
    public private(set) var received = 0
    public private(set) var errors = 0
    public private(set) var totalLatency: Double = 0
    private var measured = 0
    public private(set) var minimum: Double?
    public private(set) var maximum: Double?
    public var lost: Int { sent - received }
    public var loss: Double { sent == 0 ? 0 : Double(lost) / Double(sent) * 100 }
    public var average: Double? { measured == 0 ? nil : totalLatency / Double(measured) }
    public mutating func record(_ result: ProbeResult) {
        sent += 1
        if result.status == .error { errors += 1 }
        if result.status == .up {
            received += 1
            if let latency = result.latency {
                measured += 1
                totalLatency += latency
                minimum = min(minimum ?? latency, latency)
                maximum = max(maximum ?? latency, latency)
            }
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var interval: Double = 1
    public var timeout: Double = 2
    public var ttl: Int = 64
    public var packetSize: Int = 56
    public var columns: Int = 2
    public var launchMonitoring = false
    public var alwaysOnTop = false
    public var notifications = false
    public var sound = false
    public var logMode: String = "off"
    public var logDirectory: String = ""
    public var upColor = "36C98F"
    public var downColor = "F06A75"
    public var errorColor = "EAB65A"
    public init() {}
    public mutating func validate() {
        interval = interval.isFinite ? min(60, max(0.25, interval)) : 1
        timeout = timeout.isFinite ? min(30, max(0.25, timeout)) : 2
        ttl = min(255, max(1, ttl))
        packetSize = min(65000, max(0, packetSize))
        columns = min(4, max(1, columns))
        if !["off", "changes", "all"].contains(logMode) { logMode = "off" }
        for key in [\Settings.upColor, \Settings.downColor, \Settings.errorColor] {
            let hex = self[keyPath: key]
            if hex.count != 6 || UInt32(hex, radix: 16) == nil { self[keyPath: key] = Settings()[keyPath: key] }
        }
    }
}

public struct HistoryEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let name: String
    public let target: String
    public let event: String
    public let detail: String
    public init(date: Date = Date(), name: String, target: String, event: String, detail: String) {
        id = UUID(); self.date = date; self.name = name; self.target = target; self.event = event; self.detail = detail
    }
}

public struct Favorite: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var hosts: [HostDefinition]
    public var columns: Int
    public init(name: String, hosts: [HostDefinition], columns: Int) { self.name = name; self.hosts = hosts; self.columns = columns }
}

public struct SavedState: Codable, Sendable {
    public var version = 1
    public var settings = Settings()
    public var hosts: [HostDefinition] = []
    public var favorites: [Favorite] = []
    public var history: [HistoryEvent] = []
    public init() {}
}

public enum CSV {
    public static func field(_ text: String) -> String {
        // Prevent spreadsheet formula execution when opening a user-supplied alias.
        let safe = ["=", "+", "-", "@", "\t", "\r"].contains(String(text.prefix(1))) ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func history(_ events: [HistoryEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        return "timestamp,name,target,event,detail\r\n" + events.map {
            [formatter.string(from: $0.date), $0.name, $0.target, $0.event, $0.detail].map(field).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}

public struct StateFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        var state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        // Revalidate persisted input before it reaches a network tool.
        for host in state.hosts + state.favorites.flatMap(\.hosts) {
            guard try Target.parse(host.target.address) == host.target else { throw CocoaError(.coderReadCorrupt) }
        }
        guard Set(state.hosts.map(\.id)).count == state.hosts.count,
              Set(state.favorites.map(\.id)).count == state.favorites.count else { throw CocoaError(.coderReadCorrupt) }
        guard state.hosts.count <= 128, state.favorites.allSatisfy({ $0.hosts.count <= 128 }) else { throw CocoaError(.coderReadCorrupt) }
        state.settings.validate()
        state.history = Array(state.history.suffix(2000))
        return state
    }
    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
