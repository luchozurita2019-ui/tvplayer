# TV clásica 2 — provider playback profile

This branch contains a provider-specific compatibility profile for the authorized `tv.m3uts.xyz` service used by **TV clásica 2**.

The provider profile is isolated from ordinary M3U/Xtream playlists. It applies only when the configured dynamic source host is `tv.m3uts.xyz` and no explicit `xHash` / `TV_FULL_DYNAMIC_X_HASH` override is supplied.

Observed/authorized playback request profile:

- `X-App: di`
- `X-Version: 10/1.0.9`
- `X-Did: <ANDROID_ID>`
- `User-Agent: Magma Player/10`
- `X-Hash: <provider shared compatibility value>`

The shared provider value is intentionally kept in the provider adapter as a fallback, while explicit configuration continues to take precedence. This lets the value be replaced later without changing the Media3 engine or the Xtream catalog implementation.
