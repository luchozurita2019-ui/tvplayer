# TV FULL Native TV - IJK Architecture V1

This branch starts from `tvfull-native-complete-v1` and intentionally does not inherit the V4/V5/V6 playback experiments.

## Goals

1. Keep TV FULL remote provisioning and panel assignment as a separate subsystem.
2. Synchronize IPTV data into a local SQLite catalog before the UI consumes it.
3. Support both Xtream and M3U, with M3U as a compatibility source when the Xtream API is incomplete.
4. Resolve one final playback URL before starting a session.
5. Use IJKPlayer/FFmpeg as the native IPTV playback engine, with hardware/software decoder selection inside the same engine.
6. Keep Live, VOD and Series policies separate.
7. Never require the customer to type a long playlist URL on a TV.

## Data flow

Panel/Supabase -> RemoteProvisioning -> ProvisioningBridge -> CatalogSyncEngine -> TvCatalogDatabase -> UI -> PlaybackSourceResolver -> IjkPlaybackEngine

## Non-goals

- No source code is copied from IPTV Smarters.
- The Smarters APK is used only as an architectural/behavioral reference.
- No automatic TS-to-HLS mutation during a running playback session.
- No Media3-to-VLC/IJK engine switching after playback has already started.

## Playback policy

- A session receives one resolved URL.
- Decoder mode can be AUTO, HARDWARE or SOFTWARE.
- AUTO starts with MediaCodec and may retry the same URL once with FFmpeg software decoding after a decoder failure.
- Network reconnect stays inside IJK/FFmpeg.
- Buffer size is a native player option, not an external timer pretending to be a buffer.

## Compatibility

IJKPlayer upstream: `bilibili/ijkplayer` tag `k0.8.8`, LGPLv2.1-or-later. The official project documents MediaCodec support and Android ARMv7/ARM64 artifacts.
