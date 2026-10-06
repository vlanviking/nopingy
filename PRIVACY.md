# Privacy

## App data

nopingy does not use analytics, a remote account service, or a hosted monitoring
backend. It sends checks to the hosts you enter. Hostnames and DNS tools use your
configured DNS resolver.

Your host list, aliases, saved groups, settings, and recent status history stay
in `~/Library/Application Support/nopingy/state.json`. Optional CSV logs and
exports stay in the folder you choose. These files can contain your network
details, so review them before sharing them.

## Repository and releases

The initial public source and app release were reviewed for private data before
publication. They contain code, tests, generic examples, documentation, licenses,
and the app's generated icon. They do not include user settings, monitoring logs,
host lists, desktop screenshots, credentials, or the surrounding project files.

The release ZIP excludes Finder resource metadata, extended attributes, and
quarantine metadata. Build caches and debug-symbol bundles are excluded. The
executable was checked for local usernames, home-directory paths, and credentials.
Git commits use the repository owner's public GitHub handle and a GitHub
no-reply address.

Demo IP addresses in `192.0.2.0/24` are reserved for documentation by
[RFC 5737](https://www.rfc-editor.org/rfc/rfc5737). Other examples use loopback,
the public Cloudflare DNS service, or `example.com`. Demo mode sends no probes.

`.gitignore` excludes common local settings, host files, CSV exports, logs, and
credential files. Review any new files before committing them; an ignore rule
does not prevent someone from explicitly adding a file.
