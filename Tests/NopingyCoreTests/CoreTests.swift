import Foundation
import NopingyCore

final class CoreTests {
    func testTargetsAndIPv6Ports() throws {
        let tcp = try Target.parse("example.com:443")
        assertEqual(tcp.kind, .tcp); assertEqual(tcp.port, 443)
        assertEqual(try Target.parse("[2001:db8::1]:8443").address, "[2001:db8::1]:8443")
        assertEqual(try Target.parse("::1").kind, .icmp)
        assertEqual(try Target.parse("fe80::1%en0").host, "fe80::1%en0")
        assertEqual(try Target.parse("D/example.com").kind, .dns)
        assertEqual(try Target.parse("T/127.0.0.1").kind, .traceroute)
        assertEqual(try Target.parse("[::1]").address, "::1")
    }

    func testRejectsInvalidOrExecutableInputs() {
        for input in ["", "-c", "example.com;whoami", "$(whoami)", "a b", "host:0", "host:65536", "[::1", "[hello]:80", "[::1]:443extra", "2001:broken::", "a..com", "T/-x", "D/foo:80", "::1%en0/evil"] {
            assertThrows(try Target.parse(input), input)
        }
    }

    func testBulkAliasCommentsAndAtomicFailure() throws {
        let hosts = try HostDefinition.parseList("# A comment\nRouter = 127.0.0.1, example.com:443\n\nIPv6 = [::1]:8080 # inline comment\n")
        assertEqual(hosts.count, 3); assertEqual(hosts[0].name, "Router"); assertEqual(hosts[2].inputLine, "IPv6 = [::1]:8080")
        assertThrows(try HostDefinition.parseList("127.0.0.1\nbad;host"))
        assertThrows(try HostDefinition.parseList(Array(repeating: "localhost", count: 129).joined(separator: "\n")))
    }

    func testPingReplyLossAndErrorClassification() {
        for text in ["64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.123 ms", "64 bytes from ::1: icmp_seq=0 hlim=64 time=1.4 ms", "Reply time<1 ms"] {
            let result = ProbeEngine.parsePing(CommandOutput(text: text, exitCode: 0, timedOut: false))
            assertEqual(result.status, .up); assertNotNil(result.latency)
        }
        assertEqual(ProbeEngine.parsePing(CommandOutput(text: "100.0% packet loss", exitCode: 2, timedOut: false)).status, .down)
        assertEqual(ProbeEngine.parsePing(CommandOutput(text: "ping: cannot resolve abc: Unknown host", exitCode: 68, timedOut: false)).status, .error)
        assertEqual(ProbeEngine.parsePing(CommandOutput(text: "ping: sendto: Operation not permitted", exitCode: 2, timedOut: false)).status, .error)
    }

    func testStatisticsAcrossRepliesLossAndErrors() {
        var statistics = ProbeStatistics()
        statistics.record(ProbeResult(status: .up, latency: 10, detail: ""))
        statistics.record(ProbeResult(status: .down, detail: ""))
        statistics.record(ProbeResult(status: .up, latency: 30, detail: ""))
        statistics.record(ProbeResult(status: .error, detail: ""))
        assertEqual(statistics.sent, 4); assertEqual(statistics.received, 2); assertEqual(statistics.errors, 1)
        assertEqual(statistics.loss, 50); assertEqual(statistics.average, 20)
        assertEqual(statistics.minimum, 10); assertEqual(statistics.maximum, 30)
        var trace = ProbeStatistics()
        trace.record(ProbeResult(status: .up, detail: "Trace completed"))
        assertTrue(trace.average == nil)
    }

    func testSettingsClampingAndCSV() {
        var settings = Settings(); settings.interval = -1; settings.timeout = .infinity; settings.ttl = 999; settings.packetSize = -3; settings.columns = 0; settings.upColor = "bad"; settings.validate()
        assertEqual(settings.interval, 0.25); assertEqual(settings.timeout, 2); assertEqual(settings.ttl, 255)
        assertEqual(settings.packetSize, 0); assertEqual(settings.columns, 1); assertEqual(settings.upColor, "36C98F")
        assertEqual(CSV.field("a,\"b\""), "\"a,\"\"b\"\"\"")
        assertEqual(CSV.field("=HYPERLINK(1)"), "\"'=HYPERLINK(1)\"")
    }

    func testStateRoundTripAndCorruptionPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let file = StateFile(url: url)
        assertTrue(try file.load().hosts.isEmpty)
        var state = SavedState(); state.hosts = try HostDefinition.parseList("Router = 127.0.0.1")
        state.favorites = [Favorite(name: "Home", hosts: state.hosts, columns: 2)]
        try file.save(state)
        let loaded = try file.load()
        assertEqual(loaded.hosts, state.hosts); assertEqual(loaded.favorites.first?.name, "Home")
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try Data(json.replacingOccurrences(of: "\"kind\":\"icmp\"", with: "\"kind\":\"tcp\"").utf8).write(to: url)
        assertThrows(try file.load()) // A TCP target without a port must not reach the probe engine.
        try Data("corrupt".utf8).write(to: url)
        assertThrows(try file.load()); assertEqual(try String(contentsOf: url), "corrupt")
    }

    func testPingArgumentsMatchMacOS() throws {
        var settings = Settings(); settings.timeout = 1.5; settings.ttl = 32
        let args = ProbeEngine.pingArguments(try Target.parse("127.0.0.1"), settings: settings)
        assertTrue(args.contains("1500")); assertTrue(args.contains("32")); assertEqual(args.last, "127.0.0.1")
        let v6 = ProbeEngine.pingArguments(try Target.parse("::1"), settings: settings)
        assertTrue(v6.contains("-h")); assertFalse(v6.contains("-W")); assertEqual(v6.last, "::1")
    }

    func testCommandDeadlineAndCancellation() async throws {
        let start = Date()
        let result = try await CommandRunner.run(path: "/bin/sleep", arguments: ["5"], timeout: 0.15)
        assertTrue(result.timedOut); assertLessThan(Date().timeIntervalSince(start), 2)
        let task = Task { try await CommandRunner.run(path: "/bin/sleep", arguments: ["5"], timeout: 8) }
        try await Task.sleep(nanoseconds: 50_000_000); task.cancel()
        do { _ = try await task.value; fail("Cancellation should throw") } catch { assertTrue(error is CancellationError) }
    }
}
