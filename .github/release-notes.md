### Install

1. Download **SparkTop-universal.zip** and unzip.
2. Move **SparkTop.app** to **/Applications**.
3. First launch: right-click the app → **Open** (ad-hoc signed, so Gatekeeper asks once), or clear the quarantine flag:

   ```bash
   xattr -cr /Applications/SparkTop.app
   ```

4. The ⚡ bolt appears in the menu bar — open Settings (gear) and point it at your sparkDash server (URL + access token).

**Requirements:** macOS 13+. Universal binary (Apple Silicon & Intel).

SparkTop is a thin client for [sparkDash](https://github.com/MiaAI-Lab/sparkDash) — it renders the live fleet snapshot from your own sparkDash server. No SSH credentials ever leave the server.
