### Install

1. Download **SparkTop-universal.zip** and unzip.
2. Move **SparkTop.app** to **/Applications**.
3. First launch: right-click the app → **Open** (ad-hoc signed, so Gatekeeper asks once), or clear the quarantine flag:

   ```bash
   xattr -cr /Applications/SparkTop.app
   ```

4. The ⚡ bolt appears in the menu bar — open Settings (gear) and point it at your sparkDash server (URL + access token).

### iOS & iPadOS

`SparkTop-unsigned-<version>.ipa` is an unsigned iPhone/iPad build of the same thin client. Sideload it with [AltStore](https://altstore.io)/[SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io) (free Apple ID: 7-day re-sign), or with a paid developer account for a year-long signature. iOS asks for Local Network permission on first launch.

**Requirements:** macOS 13+. Universal binary (Apple Silicon & Intel).

SparkTop is a thin client for [sparkDash](https://github.com/MiaAI-Lab/sparkDash) — it renders the live fleet snapshot from your own sparkDash server. No SSH credentials ever leave the server.
