# nopingy

Keep an eye on your network, one host at a time.

nopingy is a native Mac app that monitors multiple hosts in one window. See
whether a host is up, watch its response time, and spot outages without switching
between terminal windows. Inspired by [vmPing](https://github.com/r-smith/vmPing).

**Requires macOS 13 or later.** The download includes Apple Silicon and Intel builds.

## Download and install

1. [Download the latest release](https://github.com/vlanviking/nopingy/releases/latest).
2. Unzip `nopingy-mac.zip` and drag **nopingy.app** into **Applications**.
3. Open **nopingy**.

The app is not notarized by Apple. If macOS blocks it, check **System Settings →
Privacy & Security → Open Anyway**. You can also build it yourself using the
instructions below.

## Start monitoring

Click **Add hosts**, enter one host per line, and click **Add hosts** again.
Monitoring starts immediately unless you turn that option off.

```text
Cloudflare = 1.1.1.1
Web server = example.com:443
This Mac = 127.0.0.1
```

`Name = target` gives a host a friendly name. You can also separate targets with
commas, import a text file, or drop a host-list file onto the window. Lines that
start with `#` are comments.

| What you see | What it means |
| --- | --- |
| **Green · Up** | A ping reply, open TCP port, or successful DNS lookup |
| **Red · Down** | No ping reply before the timeout, or a TCP connection failed |
| **Amber · Error** | A problem running the check or resolving the hostname |
| **Gray · Idle** | Monitoring is stopped; previous readings stay visible |

Use **Start all** or **Stop all** to control the whole board. Each host also has
its own Start/Pause button and a menu for editing, exporting replies, or removing
it. Closing the window keeps monitoring running in the menu bar. Choose
**Quit nopingy** to stop the app.

## Status notifications

Click **Notifications** on the monitor screen, turn on **Notify when a host
changes status**, and click **Apply**. Allow notifications when macOS asks.
You can also find this option in **Settings → Notifications**.

You'll get a Mac notification when a host changes between **Up**, **Down**, and
**Error**, including when nopingy is in front or its window is closed. Each alert
shows the host, target, previous status, and new status. The first result,
repeated results, and pausing don't create alerts.

Use **Send test notification** to check that banners appear. If permission was
denied, enable nopingy in **System Settings → Notifications**, then turn on the
app's status notifications again. macOS Focus settings may silence banners.
**Play a sound** is optional. Notifications are off until you enable them, and
demo mode never sends alerts.

## What it can do

- Monitor up to **128 hosts**, including IPv4, IPv6, and TCP ports.
- Show response-time charts, packet loss, and average latency.
- Save host groups and load them with one click.
- Filter hosts and review status changes in **Status history**.
- Export replies or history, and optionally keep daily CSV logs.
- Send macOS notifications or play sounds when a known host state changes.
- Run DNS lookups, traceroute, and finite ping bursts from **Network tools**.
- Adjust timing, payload size, TTL, columns, colors, and keep-on-top behavior.

## More target formats

| Target | Check |
| --- | --- |
| `1.1.1.1` or `example.com` | ICMP ping |
| `example.com:443` | TCP port |
| `::1` | IPv6 ping |
| `[::1]:8080` | IPv6 TCP port |
| `D/example.com` | Repeated DNS lookup |
| `D/1.1.1.1` | Reverse DNS lookup |
| `T/example.com` | One traceroute |

Traceroute runs once and retains its output. Completion does not mean the host
will remain available. Ping bursts send 10–1,000 packets, at least 0.2 seconds
apart. There are no SMTP email alerts or vmPing XML imports in this version.

## Your data stays on your Mac

There is no analytics service or account requirement. The app contacts the hosts
you choose and uses your configured DNS resolver for lookups.

Hosts, saved groups, settings, and recent status history are stored locally in:

```text
~/Library/Application Support/nopingy/state.json
```

Daily CSV logs are written only if you enable logging and choose a folder.
The app keeps 200 replies per host, displays the latest 50, and saves the latest
2,000 status events. Statistics restart when you quit.

Demo mode uses sample data and sends no probes. **Use live monitoring** or
**Add hosts** leaves demo mode and restores your saved hosts. Sample hosts and
statistics are discarded.

See [PRIVACY.md](PRIVACY.md) for what is excluded from the repository and release.

## Build from source

You need Apple's Command Line Tools or Xcode, plus Python 3 for packaging.
If the Apple tools are missing, run `xcode-select --install` first.

```sh
git clone https://github.com/vlanviking/nopingy.git
cd nopingy
bash scripts/build-app.sh
open dist/nopingy.app
```

To build for both Apple Silicon and Intel:

```sh
bash scripts/build-app.sh --universal
```

The build produces `dist/nopingy.app` and `dist/nopingy-mac.zip`. It preserves a
previous build if that app is still running. Quit and reopen after rebuilding.

<details>
<summary>Checks and command-line use</summary>

Run the core checks, then the packaged app's interface checks:

```sh
bash scripts/test.sh
dist/nopingy.app/Contents/MacOS/nopingy --check-interface
```

The core checks cover parsing, statistics, CSV output, saved configuration,
timeouts, and cancellation. The interface checks cover reply-log scrolling and
the transition from demo to live monitoring, status-change alerts, permission
handling, and notification delivery failures. Full Xcode's XCTest framework is
not required.

The optional network smoke test checks local IPv4/IPv6 and TCP services, resolves
`example.com`, and runs a loopback traceroute:

```sh
python3 scripts/smoke.py
```

Launch with targets or run a one-shot check:

```sh
open dist/nopingy.app --args 127.0.0.1 example.com:443
open dist/nopingy.app --args ./hosts.txt
open dist/nopingy.app --args --demo
dist/nopingy.app/Contents/MacOS/nopingy --probe 127.0.0.1
```

One-shot checks exit with `0` for success, `1` for down/error, and `2` for invalid
input. ICMP, DNS, and traceroute use macOS's built-in utilities with separate
arguments. TCP checks use Apple's Network framework. No targets are passed to a
shell.

</details>

## License and credits

[MIT licensed](LICENSE). nopingy is an independent implementation of vmPing's
main workflow. Thanks to Ryan Smith for the original idea. No vmPing source code
or artwork is included. See [third-party notices](THIRD_PARTY_NOTICES.md).
