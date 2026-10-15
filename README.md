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
- **Agent Mode** — generate or edit queries with Claude Code or Codex CLI
- **Multiple tabs** with independent connections (Cmd+T)
- **Connection environments** — local, dev, staging, production
- **SSH tunneling** — password or private key authentication
- **SQLite over SSH** — browse and query a VPS-hosted SQLite file from the same SQLite connection flow
- **Session persistence** — connections and tabs restore across app relaunches
- **Color-coded indicators** and connection tooltips
- Native macOS UI — no Electron, no web views

## Agent Mode

Agent Mode can create a new query or edit the current query block using a local agent CLI.

<img width="1068" height="316" alt="image" src="https://github.com/user-attachments/assets/eb78ed0f-c6ee-4293-888c-78f7c55f3072" />


- Hover a selected query block or an empty editor line, then click **agent mode**
- Press **Cmd+K** to open Agent Mode at the cursor
- Press **Cmd+Return** from the Agent Mode prompt to generate
- Press **Esc** or the close button to close Agent Mode

Cove currently supports:

- **Claude Code** via the `claude` CLI
- **Codex CLI** via the `codex` CLI

The selected agent receives the current query block, the active backend and database metadata, the loaded browser tree, and completion schema context. Cove does not send database passwords to the agent prompt.

Agent processes run locally from Cove's Application Support workspace. macOS may still show a Documents folder permission prompt if the underlying CLI tries to access a protected folder, especially when developing or launching Cove from a repository inside `~/Documents`.

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
supported. The native TNS parser validates the form; each DESCRIPTION currently
must contain one ADDRESS and specify ordered routing (`LOAD_BALANCE=OFF`).

Without XCTest (Command Line Tools only), run the standalone checks:

```bash
swiftc -parse-as-library Cove/DB/Oracle/OracleConnectionSettings.swift check-oracle.swift -o .build/check-oracle
.build/check-oracle
```

## Roadmap

Contributions welcome:

- Import/export (CSV, JSON, SQL)
- Data filtering and search
- Query history panel
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
