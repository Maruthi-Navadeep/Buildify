# Capture guide — recording the real Buildify UI for the brief

You record 6 short clips of the **real app** (and one laptop terminal). I drop them into
the brand-motion compositor (`demo-video/`) which frames them, adds the title cards,
captions, particles, and transitions, then records the finished loop.

## Where to save

Save each recording into `demo-video/clips/` with the **exact** name below (mp4 preferred).
Missing clips show as labeled placeholders, so you can preview the whole thing and add
footage one clip at a time.

| File | Frame | Target length | What to record (real app) |
|------|-------|---------------|---------------------------|
| `clips/01-new-service.mp4`     | phone  | ~6s  | Projects dashboard → tap **+ new service** → the modal showing **both** options (*run an ai model* / *host a project*). This is the "host anything" beat — linger on the two choices, then tap **run an ai model**. |
| `clips/02-model-download.mp4`  | phone  | ~6s  | The model catalog (scroll a touch), tap **CONTINUE** on a model, show the **download progress** bar filling. |
| `clips/03-start-online.mp4`    | phone  | ~7s  | ServiceDetailPage: tap **START AI SERVER** → status flips to **ONLINE**, the pulsing dot, and the **IP + port** (`192.168.x.x:8080`) appearing. |
| `clips/04-call-it.mp4`         | window | ~6s  | **Laptop terminal** running `curl` or `python basic_chat.py` against the phone, showing the response / streamed tokens. (If you'd rather show the in-app **Self-test** chat instead, record that on the phone and tell me — I'll switch this slot to a phone frame.) |
| `clips/05-tunnel-security.mp4` | phone  | ~5s  | Tap **Start Cloudflare Tunnel** → the `…trycloudflare.com` URL appears; then the **API key** + **auto-stop** guards card. |
| `clips/06-host-project.mp4`    | phone  | ~6s  | The **host-a-project** wizard: GitHub / upload → build settings → deploy → the **live endpoint**. |

Clips can be a little longer than the target — I trim to length in the timeline. Keep each
clip **focused on one action** so it reads clearly at speed.

## How to record

**On the phone (clips 01, 02, 03, 05, 06):**
- Use the built-in **Screen Record** (Quick Settings tile). 1080p, 30 or 60 fps. Audio off is fine.
- Record **portrait** (the compositor frames these in a phone bezel).
- Prep a clean device: full-ish battery, silence notifications / enable Do-Not-Disturb,
  and make sure a model is already downloaded before clip 03 so the start is instant.
- Move deliberately — a beat of hold on each key screen (the ONLINE flip, the tunnel URL)
  reads better than a fast tap.

**On the laptop (clip 04):**
- Record just the terminal window (landscape). Use a big font and a dark theme.
- Real command against the phone, e.g.:
  - `curl http://192.168.0.121:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"hi"}]}'`
  - or `python basic_chat.py` (auto-discovers, prints battery %, streams tokens).

## Preview + export

1. `cd demo-video && python -m http.server 8000` → open `http://localhost:8000`.
2. As you add clips to `clips/`, refresh — each placeholder is replaced by real footage.
3. When it looks right, press **`r`** (record). It replays one clean ~44s loop and downloads
   `buildify-brief.webm` (recorded straight off the canvas, so the real footage is included).
4. Convert to a README-friendly GIF/MP4 with the ffmpeg commands in `render.md`.

## Honesty note

Everything shown is the real app. The host-a-project **deploy is a demo flow today**, so we
keep clip 06 to the on-screen wizard (per your call, shown without a tag) and don't claim a
project is serving live traffic on the internet.
