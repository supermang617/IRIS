import assert from "node:assert/strict";
import test from "node:test";

import {
  classifyMediaActionRoute,
  classifySpotifyConnectRoute,
  mediaActionStatusText,
  spotifyClientIdFromConnectRequest,
  spotifyConnectStatusText,
  spotifyQueryFromPlaybackRequest
} from "./media-routing.js";

test("spotify playback request routes to media action", () => {
  assert.deepEqual(
    classifyMediaActionRoute("play stars in the roof of my car by Riff-Raff on spotify"),
    {
      route: "implicit",
      service: "spotify",
      query: "stars in the roof of my car by Riff-Raff",
      prompt: "play stars in the roof of my car by Riff-Raff on spotify"
    }
  );
});

test("spotify query removes control words but keeps song and artist", () => {
  assert.equal(
    spotifyQueryFromPlaybackRequest("Iris, please put on the song Stars in the Roof of My Car by Riff Raff using Spotify"),
    "Stars in the Roof of My Car by Riff Raff"
  );
});

test("ordinary play requests do not route without Spotify target", () => {
  assert.deepEqual(classifyMediaActionRoute("play a story about a car"), {
    route: "none",
    service: null,
    query: "",
    prompt: "play a story about a car"
  });
});

test("media action status avoids promising playback completion", () => {
  assert.equal(
    mediaActionStatusText({ service: "spotify" }),
    "Opening Spotify."
  );
});

test("spotify connect request routes to one-time authorization", () => {
  assert.deepEqual(classifySpotifyConnectRoute("spotify connect abc123DEF456"), {
    route: "spotify-connect",
    action: "connect",
    clientId: "abc123DEF456",
    prompt: "spotify connect abc123DEF456"
  });
});

test("spotify status request routes to connection status", () => {
  assert.deepEqual(classifySpotifyConnectRoute("is spotify connected"), {
    route: "spotify-connect",
    action: "status",
    clientId: "",
    prompt: "is spotify connected"
  });
});

test("spotify connect extracts the client id without keeping setup words", () => {
  assert.equal(
    spotifyClientIdFromConnectRequest("Iris, connect Spotify with client id abc123DEF456"),
    "abc123DEF456"
  );
});

test("spotify connect status text stays action-oriented", () => {
  assert.equal(
    spotifyConnectStatusText({ action: "connect" }),
    "Starting Spotify connection."
  );
  assert.equal(
    spotifyConnectStatusText({ action: "status" }),
    "Checking Spotify connection."
  );
});
