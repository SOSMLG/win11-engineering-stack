# qBittorrent

Fresh installs only. The staged file lands at
`%APPDATA%\qBittorrent\qbittorrent.ini`. Existing user settings are kept.

## shipped state

- WebUI off. The address is loopback only if you enable it locally.
- No web username or password hash in this repo. Set a password in the app if
  you turn WebUI on; it stays in your user config.
- Save path `C:/Users/Public/Downloads`. Change it here or in Preferences before
  starting a download.
- UPnP off. DHT, Peer Exchange, and Local Peer Discovery on.
- Queue 5 active downloads and 5 active uploads.
- Native light UI. No custom theme or dark injection.

## notes

- If WebUI is on, bind it to `127.0.0.1` and use a strong local password. Do not
  forward port 8080 to the LAN.
- Encryption, port forwarding, disk cache, and anonymous mode are left at your
  discretion. Anonymous mode breaks private trackers; use it for public swarms
  only.
- Search plugins need Python, which the daily profile installs. Check for plugin
  updates inside the app when you actually use the Search tab.
