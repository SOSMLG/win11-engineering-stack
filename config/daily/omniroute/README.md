# omniroute notes

source: https://github.com/diegosouzapw/OmniRoute

install: `npm install -g omniroute`, then run `omniroute`.
dashboard: http://localhost:20128

create a key at http://localhost:20128/dashboard/api-manager and set it for your user:

```powershell
setx OMNIROUTE_API_KEY "your-key-here"
```

`setup.ps1` never writes a key to a file. it only installs the opencode config that reads
`OMNIROUTE_API_KEY` from the environment. verify with:

```powershell
curl http://localhost:20128/v1/models -H "Authorization: Bearer $env:OMNIROUTE_API_KEY"
```

base URL for tools is `http://localhost:20128/v1`. `127.0.0.1` is used in opencode.json so ipv6
resolution cannot send the request to the wrong listener. model ids: `auto`, `auto/coding`,
`auto/fast`. `auto` skips providers marked `tos: avoid`.
