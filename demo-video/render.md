# Buildify README brief — render guide

A **~44s, 1280×720, looping** brief that composites your **real app screen recordings**
into the brand motion (title cards, captions, particles, phone/terminal frames, fades),
built with **p5.js** (+ optional **Tone.js** audio for a sound-on cut).

```
demo-video/
├─ index.html     ← open this in a browser
├─ sketch.js      ← compositor: segment timeline + frames + captions + recording
├─ clips/         ← put your real recordings here (see CAPTURE.md)
├─ CAPTURE.md     ← what to record and how
└─ render.md      ← you are here
```

## 1. Preview

```bash
cd demo-video
python -m http.server 8000      # or: npx serve .
# open http://localhost:8000
```

> Use `http://localhost`, not `file://`, so the CDN scripts, fonts, and local clips load.

Missing clips render as labeled placeholders, so the whole loop previews (as a storyboard)
before any footage exists. Add files to `clips/` and refresh to swap placeholders for real
footage. Controls: `space` pause · `r` record · `m` sound on/off.

## 2. Timeline

Edit durations, captions, and frame types in the `SEG` array at the top of `sketch.js`.
Each segment is `title` (intro), `phone` (portrait clip in a bezel), `window` (landscape
laptop clip), or `outro`. Cumulative starts and total length are computed automatically —
just change a `dur` and everything reflows.

Slots: intro → new-service (both paths) → model+download → start→ONLINE → call-it (laptop) →
tunnel+security → host-a-project → outro.

## 3. Export the loop (for the README)

1. Open the page, press **`r`** (or the "record webm" button).
2. It restarts at frame 0, plays one clean loop, and downloads **`buildify-brief.webm`**.
   Recording is done with `MediaRecorder` on the canvas stream, so the **real video frames
   are captured** (not just the drawn overlays).
3. Convert with ffmpeg:

**MP4** (upload to a GitHub issue/release; plays muted, loops):
```bash
ffmpeg -i buildify-brief.webm -movflags +faststart -pix_fmt yuv420p -vf "scale=1280:-2" -crf 20 buildify-brief.mp4
```

**GIF** (drops straight into README markdown; larger, always autoplays):
```bash
ffmpeg -i buildify-brief.webm -vf "fps=20,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 buildify-brief.gif
```

Embed:
```md
![Buildify demo](https://user-images.githubusercontent.com/…/buildify-brief.gif)
<!-- or MP4 uploaded to an issue/release: -->
https://github.com/NavadeepDj/Buildify/assets/…/buildify-brief.mp4
```

> GitHub READMEs autoplay **muted**, so the README cut is silent — expected.

## 4. Sound-on cut (website / social)

`MediaRecorder` here records the canvas video only. For a sound-on version, either:
- press **`m`** to enable the Tone.js cues and screen-record the tab **with audio** (OBS), or
- mux a separate audio track onto the MP4:
  ```bash
  ffmpeg -i buildify-brief.mp4 -i demo-audio.wav -c:v copy -c:a aac -shortest buildify-brief-sound.mp4
  ```

For a **1080×1080 square** cut, set `W`/`H` at the top of `sketch.js` to `1080, 1080` and
nudge the frame coordinates, then re-record.

## 5. Notes

- Recording is **real-time** (one ~44s pass) — don't switch tabs while it records, or the
  browser may throttle the canvas stream.
- The outro fades toward the opening particle field, so the loop seam is clean.
- Pinned CDN builds: p5.js 1.9.4, Tone.js 14.8.49 (see `index.html`). CCapture is no longer
  used — capture is via `MediaRecorder`, which handles the video frames correctly.
- The full cinematic demo comes later; this brief's footage and structure feed straight into it.
```
