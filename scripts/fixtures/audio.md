# Playback fixture

`audio.m4a` is a generated 90-second, 220 Hz mono tone at 44.1 kHz, encoded as AAC at 64 kbit/s. It contains no recorded music. UI tests use the same M4A/AAC container as normal application playback, including byte-range requests and seeking.

Reproduce with FFmpeg:

```sh
ffmpeg -f lavfi -i 'sine=frequency=220:sample_rate=44100:duration=90' -ac 1 -c:a aac -b:a 64k -movflags +faststart audio.m4a
```
