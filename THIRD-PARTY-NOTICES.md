# third-party notices

this repo configures and installs other people's software. it owns none of it.
the license column is blank on purpose: confirm each one yourself before relying on it.

## installed by the installer (not stored in this repo)
engines per app, first hit wins: staged `-OfflineDir` files, winget, Chocolatey, GitHub releases.

| item | ids / source | license (confirm) |
|---|---|---|
| Helium | `ImputNet.Helium` | |
| VSCodium | `VSCodium.VSCodium` | |
| Vesktop | `Vencord.Vesktop` | |
| Telegram Desktop | `Telegram.TelegramDesktop` | |
| MercuryGram (manual) | v7.4.4.1 portable, hash in `docs/RESEARCH.md` | |
| qBittorrent, VLC, OBS Studio | `qBittorrent.qBittorrent`, `VideoLAN.VLC`, `OBSProject.OBSStudio` | |
| Git, Node.js LTS, Python 3.12, 7-Zip | `Git.Git`, `OpenJS.NodeJS.LTS`, `Python.Python.3.12`, `7zip.7zip` | |
| Wireshark | `WiresharkFoundation.Wireshark` | |
| opencode | `SST.opencode`. CI also installs `opencode-ai@1.19.4` from npm to validate configs | |
| shell pack | Starship, zoxide, fzf, bat, eza, Fastfetch | |
| Windows Terminal | `Microsoft.WindowsTerminal` | |
| optional (`-IncludeOptional`) | Obsidian, Spotify | |
| runtimes | VC++ 2005 to 2022, .NET 8 Desktop Runtime | |
| Chocolatey | bootstrapped when missing |
| context7 MCP, Playwright MCP | `@upstash/context7-mcp@4.4.4`, `@playwright/mcp@0.0.83`, fetched by `npx` the first time OpenCode starts them | |

## stored in this repo
| item | where | license (confirm) |
|---|---|---|
| Darkmatter VSCodium theme | `VSCodium/darkmatter-theme/` | |
| system24 darkmatter quickcss | `Vesktop/quickcss.css` | |

add the license name and a link for each row. include a copy of any license that requires one.
