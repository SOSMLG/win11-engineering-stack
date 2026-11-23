# ventoy drop-in

rufus path needs nothing. ventoy skips $OEM$, so it needs this folder.

## use
1. build your own windows install media and copy it to the ventoy stick.
2. copy this `ventoy` folder to the stick root (stick ends up with
   `/ventoy/ventoy.json` and `/ventoy/script/Win-Iot-unattended.xml`).
3. boot the media. install runs unattended, no menu.

## notes
- the answer file expects this repo staged at `C:\Setup` and runs
  `Install.ps1 -Profile iot` from there on first logon.
- no net on first boot? stage installers beside the repo or tether the phone
  when the log asks.
