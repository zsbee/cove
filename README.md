# Cove

[![Build](https://github.com/emanuele-em/cove/actions/workflows/build.yml/badge.svg)](https://github.com/emanuele-em/cove/actions/workflows/build.yml)
[![Download](https://img.shields.io/github/v/release/emanuele-em/cove?label=Download&style=flat)](https://github.com/emanuele-em/cove/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000.svg?logo=apple)](https://developer.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white)](https://swift.org)

A native macOS database client. Fast, lightweight, extensible.

![Cove demo](docs/hero.gif)

### Supported databases

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/postgres-logo.imageset/postgres-logo.png" width="40"><br><b>PostgreSQL</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mysql-logo.imageset/mysql-logo.png" width="40"><br><b>MySQL</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mariadb-logo.imageset/mariadb-logo.png" width="40"><br><b>MariaDB</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/sqlite-logo.imageset/sqlite-logo.png" width="40"><br><b>SQLite</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/mongodb-logo.imageset/mongodb-logo.png" width="40"><br><b>MongoDB</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/redis-logo.imageset/redis-logo.png" width="40"><br><b>Redis</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/scylladb-logo.imageset/scylladb-logo.png" width="40"><br><b>ScyllaDB</b></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/cassandra-logo.imageset/cassandra-logo.png" width="40"><br><b>Cassandra</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/elasticsearch-logo.imageset/elasticsearch-logo.png" width="40"><br><b>Elasticsearch</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/oracle-logo.imageset/oracle-logo.png" width="40"><br><b>Oracle</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/sqlserver-logo.imageset/sqlserver-logo.png" width="40"><br><b>SQL Server</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/clickhouse-logo.imageset/clickhouse-logo.png" width="40"><br><b>ClickHouse</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/emanuele-em/cove/refs/heads/main/Cove/Assets.xcassets/duckdb-logo.imageset/duckdb-logo.png" width="40"><br><b>DuckDB</b></td>
  </tr>
</table>

Adding a new backend requires zero changes to UI code — see [`DB/README.md`](Cove/DB/README.md).

## Features

- **Browse** schemas, tables, views, indexes, and keys in a sidebar tree
- **Edit rows** inline with SQL/CQL preview before commit
- **Run queries** with syntax highlighting and autocomplete
- **Query history** — the latest 100 queries across connections, with persistent starred favorites and offline preview
- **Agent Mode** — generate or edit queries locally with Ollama, or with Claude Code or Codex CLI
- **Multiple tabs** with independent connections (Cmd+T)
- **Connection environments** — local, dev, staging, production
- **SSH tunneling** — password or private key authentication
- **SQLite over SSH** — browse and query a VPS-hosted SQLite file from the same SQLite connection flow
- **Session persistence** — connections and tabs restore across app relaunches
- **Color-coded indicators** and connection tooltips
- Native macOS UI — no Electron, no web views

## Query History

Open the right-hand panel with the **Query History** toolbar button or **Shift+Cmd+H** (View → Query History). It is available without an active connection and shared across all tabs, connections, and environments.

- Explicit editor runs save the submitted selection or current block, including failed queries. Repeating identical SQL updates its timestamp rather than creating a duplicate.
- **Starred** queries stay at the top and are never automatically removed. The editor's star button saves the current selection or block without executing it.
- **Recent** keeps the latest 100 unstarred queries. Search matches full query text in both sections.
- Select a query to preview and copy its full text, even when disconnected. **Insert in Editor** requires a connection and appends a new block without replacing existing SQL or executing anything.
- Right-click a query to delete it. **Clear Recent** in the panel's actions menu removes only unstarred queries.

History is saved locally in `~/Library/Application Support/Cove/query-history.json`, separately from connection-scoped editor drafts. SQL is stored as plain text and may contain sensitive literals; no results or connection credentials are added. Existing drafts are not imported as historical executions. Deleting a connection does not delete history.

## Agent Mode

Agent Mode can create a new query or edit the current query block. Ollama runs inference locally; Claude Code and Codex CLI may send context to their cloud providers.

<img width="1068" height="316" alt="image" src="https://github.com/user-attachments/assets/eb78ed0f-c6ee-4293-888c-78f7c55f3072" />


- Hover a selected query block or an empty editor line, then click **agent mode**
- Press **Cmd+K** to open Agent Mode at the cursor
- Press **Cmd+Return** from the Agent Mode prompt to generate
- Press **Esc** or the close button to close Agent Mode

Cove currently supports:

- **Ollama (Local)** via its localhost HTTP API (the default)
- **Claude Code** via the `claude` CLI
- **Codex CLI** via the `codex` CLI

The selected agent receives the current query block, the active backend and database metadata, the loaded browser tree, and completion schema context. Cove does not send database passwords to the agent prompt.

Agent processes run locally from Cove's Application Support workspace. macOS may still show a Documents folder permission prompt if the underlying CLI tries to access a protected folder, especially when developing or launching Cove from a repository inside `~/Documents`.

### Local Oracle SQL assistant

1. Install [Ollama](https://ollama.com/). Cove starts it automatically in the background when Cove launches, and retries when local AI is used. No terminal is needed for everyday use.
2. Download a coding model: `ollama pull qwen2.5-coder:14b` (roughly 9 GB). For less memory/download use `qwen2.5-coder:7b` instead.
3. Connect to Oracle and select the owner/schema in the browser. Open the query editor and press **Cmd+K**.
4. Choose **Ollama (Local)**. Open the gear button for **Local AI Settings**, select the installed model, and **Test Connection**.
5. Describe a query or edit, then press **Cmd+Return**. Review the SQL and run it yourself.

Cove's Ollama integration accepts only loopback HTTP endpoints, does not follow redirects, and rejects cloud models. There is no automatic cloud fallback. It supplies your request, current SQL, and scoped schema metadata—not connection credentials, hostnames, or result rows. Oracle metadata includes column types and ordered primary/foreign-key columns for the active owner; other owners and synonyms are not automatically loaded. Select a different owner to change scope. Mention exact table names or select a table to focus a large schema.

AI metadata is cached for five minutes per connection/active schema. The refresh button clears the cache for the next generation. The gear button configures endpoint, model, and timeout using separate `queryAI.ollama.*` preferences; it does not migrate or overwrite saved connections or Keychain entries.

**Start Ollama automatically with Cove** is enabled by default and can be turned off in Local AI Settings. Cove reuses an existing local server without taking ownership of it. If Cove starts a server, it binds to the configured loopback address, disables Ollama cloud access, and stops that server when Cove quits. Missing Ollama or startup failures do not block normal database browsing; AI actions report the error. Models are not downloaded or loaded into memory just by launching Cove.

Generated SQL is never executed automatically. Missing-context responses, malformed/truncated output, and failed requests leave editor text unchanged. Model output still requires review: these checks do not prove Oracle SQL correctness or prevent a manually executed query from modifying data.

Standalone local-AI checks (no database connection or app launch):

```bash
swiftc -swift-version 6 -parse-as-library \
  Cove/Agents/QueryAgentTypes.swift Cove/Agents/LocalQuerySettings.swift \
  Cove/Agents/OllamaQueryClient.swift Cove/Agents/LocalQueryContextBuilder.swift \
  Cove/Agents/OllamaServer.swift Cove/Agents/ExecutableResolver.swift \
  Cove/DB/CompletionTypes.swift Cove/DB/QueryDatabaseSchema.swift \
  Checks/LocalQueryCheck/main.swift -o .build/check-local-query
.build/check-local-query
# Optional: test start/reuse/stop/restart on a temporary local port.
.build/check-local-query --startup
# Optional: generate sample Oracle SQL against a synthetic schema using Ollama.
.build/check-local-query --live
```

## Install

Download the latest `.dmg` from [Releases](https://github.com/emanuele-em/cove/releases/latest).

> On first launch, macOS may block the app. Right-click the app and select **Open** to bypass Gatekeeper.

Or build from source:

```bash
# One-time Xcode setup, if needed
xcodebuild -runFirstLaunch

xcodebuild -scheme Cove -derivedDataPath .build build
open .build/Build/Products/Debug/Cove.app
```

If `xcodebuild` fails because Xcode has not completed setup on your machine, run `xcodebuild -runFirstLaunch` once and retry.

Requires macOS 15+.

### Build without Xcode

With Apple's Command Line Tools and Homebrew on Apple Silicon:

```bash
brew install duckdb
python3 build-and-run.py
```

This builds and opens `.build/Cove.app`, including database logos, the app icon,
and the DuckDB library. To reopen it later, use `open .build/Cove.app`.
Pass `--build-only` to skip launching.

To build and install into `~/Applications`, using the same prerequisites:

```bash
make install
```

This builds `.build/Cove.app`, copies the complete bundle to
`~/Applications/Cove.app`, and launches the installed app. Quit Cove before
updating. Existing connections, query history, preferences, and Keychain entries
are left untouched.

```bash
make install OPEN_APP=0                     # Install without launching
make install INSTALL_DIR="/custom/path"     # Use another absolute directory
make build                                 # Build without installing or launching
make run                                   # Open the installed app
make test-install                          # Test installs/updates in a temporary directory
```

The installer verifies the copied app's signature before replacing an existing
Cove bundle and refuses to overwrite unrelated files or symlinks. No `sudo` is
needed for the default install location.

The script uses the installed macOS 26.5 SDK when available because the macOS 27
Command Line Tools SDK lacks the SwiftUI macro plugin. Set `COVE_SDK` to override
the SDK path. It also applies a local OracleNIO workaround for Swift 6.4's
`@TaskLocal` attribute expansion bug. The Swift package constrains Collections
and Async Algorithms to versions compatible with the older SDK.

### Oracle TNS connections

Select **Oracle → TNS** in New Connection. Choose the **TNSADMIN** directory,
enter or select a **TNS name**, and provide your database username/password.
Alternatively, paste `jdbc:oracle:thin:@alias?TNS_ADMIN=/path/to/wallet` into
**URL override**; a nonempty URL overrides the directory and alias fields.

TNS connections use a local Oracle JDBC Thin helper for SCAN listener redirects,
DNS address failover, and Oracle auto-login wallets (`cwallet.sso`). Java 17+ is
required. The build script compiles the helper and copies the Oracle 23.26.2
driver/wallet libraries installed by IntelliJ into the local app bundle.
Database passwords travel over the helper's stdin pipe, never command-line
arguments. Basic connections continue to use OracleNIO. TNS-over-SSH is not
supported. Cove checks that `tnsnames.ora` parses and contains the selected alias;
JDBC interprets the original descriptor, including `LOAD_BALANCE=ON`, multiple
addresses, and failover settings. Cove does not rewrite the TNS file or force
ordered routing.

Without XCTest (Command Line Tools only), run the standalone checks:

```bash
swiftc -parse-as-library Cove/DB/Oracle/OracleConnectionSettings.swift check-oracle.swift -o .build/check-oracle
.build/check-oracle
```

## Roadmap

Contributions welcome:

- Import/export (CSV, JSON, SQL)
- Data filtering and search
- SSL/TLS certificate configuration UI
- Query explain/analyze visualization
- Homebrew cask

## Community

- [Bug reports](https://github.com/emanuele-em/cove/issues/new?template=bug_report.md)
- [Feature requests](https://github.com/emanuele-em/cove/issues/new?template=feature_request.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

[MIT](LICENSE)
