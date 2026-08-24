# Spotify connection for Iris

Iris can open Spotify search without account setup. Direct playback control requires Spotify Web API authorization.

## One-time Spotify setup

1. Open the Spotify Developer Dashboard.
2. Create an app.
3. Add this redirect URI exactly:

   ```text
   http://127.0.0.1:17987/spotify/callback
   ```

4. Copy the app Client ID.
5. In Iris, type:

   ```text
   spotify connect <client id>
   ```

6. Authorize Iris in the browser.

After this, requests like `play Stars in the Roof of My Car by Riff Raff on Spotify` use the Spotify Web API first.

## Required Spotify conditions

- Scope: `user-modify-playback-state user-read-playback-state`
- A Spotify Premium account is required for direct playback control.
- A Spotify app/device must be active. Open Spotify and start any song once if Spotify reports no active device.

If those conditions are not met, Iris falls back to opening the Spotify Web Player Tracks search with the requested query prefilled instead of claiming playback succeeded or resuming unrelated paused audio.
