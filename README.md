# Swift Image Forge

Everything you do to an image that is not a filter: resize, crop, convert,
compress, pad, turn, trim, and write icons and animations — offline, on
CoreGraphics and ImageIO, no dependencies.

```swift
import ImageForge

// A photo bounded and converted, with its HDR gain map intact.
let result = try await ImageForge.process(photo, to: output, options: ProcessOptions(
    operations: [.resize(.longestSide(2048))],
    encode: .format(.heic, quality: 0.8)
))
result.gainMapPreserved   // true
result.savingsRatio       // 0.83

// A square thumbnail centred on whatever the eye goes to first.
try await ImageForge.process(photo, to: thumb, options: ProcessOptions(
    operations: [.resize(.fill(width: 400, height: 400, anchor: .smart))],
    encode: .format(.jpeg)
))

// Under 500 KB, whatever quality that takes.
try await ImageForge.process(photo, to: attachment,
                             options: ProcessOptions(encode: .underBytes(500_000, format: .jpeg)))
```

## Features

- 🖼️ **62 formats in, 22 out** — every RAW this Mac knows, HEIC, AVIF, WebP,
  JPEG XL, DICOM, EXR in; PNG, JPEG, HEIC, AVIF, TIFF, GIF, ICNS, ICO and the
  rest out. The lists are read from ImageIO at runtime, never baked in
- ☀️ **HDR gain maps survive** — a modern phone photo is an SDR base plus a
  gain map, and a gain map is *not part of a `CGImage`*. Resize or convert one
  the obvious way and the HDR is silently gone. Where ImageIO can do the job
  on the destination, this library hands the source straight across and keeps
  it; where it cannot, ``ProcessResult.lostGainMap`` says so out loud
- 🎯 **Smart crop, by a hierarchy** — `.smart` asks for faces first, then
  people, then animals, then objects, then attention, stopping at the first
  that answers. A face is a fact; attention is a guess, and the result says
  which one you got
- 🔎 **The whole detection surface** — `detect` returns faces (with roll, yaw,
  pitch and capture quality), people (with an upper-body flag), cats and dogs,
  object and attention regions, a photographed page's four corners, rectangles,
  the horizon's angle, an aesthetics score and whether the image is a utility
  shot
- 📐 **Straighten** — `.straighten()` levels a picture on Vision's horizon and
  cuts back to the largest rectangle with none of the empty corners in it
- 📄 **Scanning** — `ImageForge.scan` finds the page in a photograph of one,
  flattens it with a perspective correction, keeps the shape it measured (or
  A4/Letter's within 2% when asked — `.snapping`; shape alone misnamed real pages), and cleans it in colour, grey or
  black and white. `writePDF` puts pages into a PDF as JPEG data with an
  optional invisible text layer, so a reader's words make it searchable. The
  steps are recipe operations too: `.findPage`, `.perspective`, `.cleanDocument`
- 📉 **Byte budgets** — "under 500 KB" is answered by searching quality in a
  fixed eight encodes, and refused with a message telling you to resize when
  no quality can reach it
- 📍 **Location dropped by default** — the metadata policy is
  `.stripLocation`, because a resize for the web is exactly when the
  coordinates of somebody's house leak. `.keep`, `.captureOnly` and `.strip`
  are all one word away
- 🎞️ **Animation** — read any animated format's frames with their real
  per-frame delays, write GIF, APNG or animated HEIF; reverse, ping-pong,
  thin by stride
- 🍎 **Icons** — `.icns` and `.ico` containers and `@1x/@2x/@3x` sets, with the
  sizes each container *actually* accepts (they are not the ones you expect)
- 🧩 **Compositing** — layers onto a colour, a picture or transparency, each
  with an outside stroke, a drop shadow and an outer glow (Photoshop's layer
  styles, by definition); anchors with insets in px or %, fit-to-canvas, and a
  canvas that sizes itself to a sticker and everything it casts. Float and
  premultiplied throughout, so soft edges keep no fringe and HDR survives
- 📐 **Arithmetic you can test** — every rectangle is worked out in `Geometry`,
  in top-left origin pixels, with no image in sight
- 📋 **Recipes are data** — `[ImageOperation]` is `Codable`, so a job is a JSON
  file, and the result reports the operations *as resolved* — a `.smart`
  anchor comes back as the rectangle Vision chose
- ⚡ **Decodes only what it needs** — a downscale decodes at the target size,
  so a 50-megapixel photo never has 50 megapixels in memory
- 📦 **Zero dependencies** — CoreGraphics, ImageIO and Vision; headless, no UI
  framework

## Measured

Everything below was measured on this machine, not assumed. Three of the four
contradicted the obvious guess.

**Codecs (macOS 27).** ImageIO reads 62 uniform types and writes 22.
`org.webmproject.webp` and `public.jpeg-xl` are in the read list and *not* in
the write list: **WebP cannot be encoded on Apple platforms.** Asking for it
throws an error naming AVIF, which is the writable format answering the same
brief. `isWritable` asks the running system, so a future OS that gains WebP
output starts returning `true` with no code change here.

**Icon sizes.** Written one at a time and checked at finalise:

| Container | Accepts | Refuses |
|---|---|---|
| `.icns` | 16, 24, 32, 48, 128, 256, 512 | **64**, **1024**, 20, 40, 72, 96, 180 |
| `.ico` | 16, 24, 32, 48, 64, 72, 128, 256 | 512, 1024, 20, 40, 96, 180 |

`.icns` refuses 64 — the size in the middle of the run every icon guide
lists — and refuses 1024, which is what macOS asks for as 512@2x. An
unsupported size is *accepted* by `CGImageDestinationAddImage` and only
rejected at finalise, losing the whole file rather than the one size, so
sizes are checked before anything is written.

**Gain maps.** A synthetic HEIC carrying a real gain map goes through both
roads in the test suite, and the assertions read the *file on disk*, not the
library's own report: a resize and a format change keep it; a crop, a PNG
target, a tone map and a byte budget all lose it, and each says so.

**On real photographs.** Three Unsplash JPEGs, 24 / 44 / 33 megapixels:

| | 4000×6000 | 5405×8103 | 5154×6442 |
|---|---|---|---|
| describe (header only) | 1.4 ms | 1.4 ms | 1.0 ms |
| resize to 2048, JPEG | 3.99 MB → 487 KB, 0.24 s | 5.02 MB → 713 KB, 0.32 s | 1.33 MB → 330 KB, 0.18 s |
| → HEIC q0.8 | 296 KB | 330 KB | 116 KB |
| → AVIF q0.8 | **132 KB** | 278 KB | **70 KB** |
| under 200 KB | 192 KB | 195 KB | 169 KB |

Describing a 44-megapixel file takes about a millisecond, because nothing is
decoded. A full resize of one takes a third of a second, because the decode
happens straight to the target size. And at a nominal quality of 0.8, **AVIF
came out 40–55 % smaller than HEIC** on the same images.

**Smart crop, honestly.** On those three photographs, cropped square: the
attention model moved the crop 182 px on one and agreed with the centre to
within 10 px on the other two. Where it moved, it was right — it kept the
subject and their desk instead of a third of a frame of empty floor. It is
worth having; it is not a different answer every time.

**What the detectors found.** On the same three: a face (quality 0.71, yaw
−24°, so a three-quarter view) and the person holding it; a person with no
detectable face, turned away from the camera; and, on the landscape, no named
subject at all. The hierarchy picked `face`, `person` and `object`
respectively — which is the point of having one. Detection runs in about
250–350 ms at 2048 px, after a first call that pays ~4 s to load the models.

**The document floor, measured.** `DetectDocumentSegmentationRequest` reported
a document at **0.20 confidence on a landscape photograph with no page in it**,
and it won the subject hierarchy, producing a nonsense crop. Synthetic pages
photographed at 0°, 4° and 9° of skew came back at **0.89, 0.92 and 0.98**. So
the floor is 0.5, in the middle of that gap — and documents were taken out of
the automatic hierarchy entirely, because a detector that can be wrong about
the whole subject of a picture does not belong in the path everything takes by
default. Ask for it with `.documents` when you know you have one.

**The horizon's sign, measured.** Rather than guess which way Vision's angle
runs, a photograph was tilted by known amounts and the reading taken: +3° in
gave +3.00° back, −6° gave −6.00°, +8° gave +8.13°. Levelling is therefore a
turn by the negation, which is what `.straighten()` does.

**Scanning, on synthetic pages.** An A4 page of real text, warped onto a
2400 px desk by a known perspective at seven tilts, from square-on to the far
edge 30% narrower than the near one. At every tilt: Vision found the page at
0.99, **no corner was more than 18 px out (0.75% of the frame)**, the
flattened shape snapped to A4, and all six lines read back exactly. Two
honest limits. The recogniser read the *unflattened* photograph just as well,
so what scanning buys is the artefact — a straight, searchable page a person
can file — not better OCR. And the warp narrows the far edge without
shortening the page as a real lens does, so how often a real phone photo
lands within 4% of A4 is **not yet measured on real photographs**; when it
does not, the measured shape is kept rather than forced. The text layer was
probed through PDFKit: it reads back verbatim, and a search highlights the
word within a few points of where the picture shows it.

**Scanning, on real photographs.** Sixteen photos from Wikimedia Commons
(public domain and CC BY / BY-SA — receipts, a letter, a page on a stack, plus
flat scans and two non-pages as controls), run through `img scan` 0.5.0 in
3.4 s together:

| | |
|---|---|
| A whole receipt or page on a contrasting surface (6) | 5 found and flattened cleanly — a crumpled till roll, a Spanish card slip, a hotel bill, an old handwritten letter, the top sheet of a stack. **Missed:** a receipt on yellow continuous-form paper over a yellow cloth — too little contrast for Vision's page detector |
| A receipt cut off by the frame (3) | all 3 found, cropped to the paper |
| White paper on a white table (1) | found at 0.94, flattened |
| Flat scans and screenshots (4) | all kept whole, "no page found" — the right answer |
| Not a page: a folder on a desk, a framed sign (2) | the folder kept whole; the sign found at 0.85 and flattened — a sign is a rectangle |

- **OCR is the same either way when the photo is near square-on**, and better
  when it is not: an A4 letter shot at a steep angle read 7 lines raw and 14
  flattened (address and salutation recovered). Totals and dates read the same
  before and after on every receipt.
- **Foreshortening is real, and large.** That steep A4 letter measured 1.14
  long side over short (true: 1.414), 19% off — far outside the 4% snap, so it
  kept its squashed shape. Snapping helps only photos taken nearly square-on,
  where the measured shape was close already.
- **Snapping by shape alone misfires on slips.** A Swiss hotel bill measured
  1.608 and became US Legal (1.647, 2.4% away); the framed sign measured 1.260
  and became Letter (2.6% away). Across all ten pages found, shape matching
  named the right sheet **never** and the wrong one twice. **So from 0.4.0 it
  is off by default** — the measured shape is kept, and a PDF page takes the
  picture's own size at 300 dpi — and `.snapping` / `--paper auto` opts in at
  2% (under both misfires), A4 and Letter only.

**Core Image adds alpha.** Its renders come back RGBA whatever went in, so a
flattened JPEG reported transparency and wrote a larger PNG. The page steps
take the alpha away again when the source had none — found by running the
CLI, not by a test, and now tested.

**Negative rectangles.** `CGRect.width` reports the absolute value, so an
inset that eats the whole image comes back as a positive rectangle facing
backwards. Sizes are checked as plain numbers before a rectangle is built —
a test caught this, not a review.

## Compositing (0.5)

```swift
// A product shot: the cut-out at 80% of a white square, with a soft shadow.
let shot = try ImageForge.compose(Composition(
    backdrop: .color(.white), size: CGSize(width: 1200, height: 1200),
    layers: [CompositeLayer(image: cutout, style: LayerStyle(
        placement: LayerPlacement(size: .fit(0.8)),
        effects: LayerEffects(shadow: DropShadow(offsetY: 24, blur: 40))))]))
```

- **Stroke** sits outside the layer's edge, like Photoshop's stroke with its position set to Outside; the layer itself is never covered.
- **Shadow `blur` and glow `radius`** are softening distances: a Gaussian with σ = value / 3, faded to nothing that far past an edge.
- **Effects start from the layer's silhouette** in their colour (source-in), which keeps the colour colour-managed. A colour-matrix bias would set it in the linear working space, so an sRGB 50% grey would come out at 0.73.
- **Blending** is source-over only, in gamma-encoded extended sRGB, as Photoshop, browsers and ffmpeg blend. Core Image's default linear light would make a 50% black shadow on white 188 grey instead of 128. The working space is extended, so values above 1 survive. The rest of Photoshop's styles wait for an app that needs them.

Measured on synthetic layers (`ComposeTests`):

| Check | Result |
|---|---|
| Core Image blur radius vs Gaussian σ, 3–24 px | radius = σ within 4%, so σ = blur / 3 is exact |
| Shadow offset (300, 14), blur 30 | edges at 320…440 and 234, as asked; edge goes from 90% to 10% over 26 px (2.563σ = 25.6) |
| Stroke 6 px on a 40 px square | 52 px covered; outline #808080 reads 0.502 in sRGB |
| Glow radius 15 | 0.46 alpha at the edge, 0.0 at 15 px |
| Soft-alpha white disc on white, at 1×, 0.5× and 1.7× | max deviation from white **0.0** (no fringe) |
| Transparent canvas, layer with stroke + shadow + glow | alpha and colour exactly 0 past the effects |
| A value of 4.0 in extended linear sRGB | comes back 4.0 in a 16-bit result |
| Anchor bottom-right, inset 7 px | lands on the exact pixel |
| A hard 50% black shadow on white | 128 of 255, as in Photoshop |
| A real `cutout` PNG (stock parrot, soft mask) over blue vs ffmpeg's RGB overlay | max difference 1/255, mean 0.06, over 262,144 pixels |

## What this library does not do

Colour and tone — with one exception, `.cleanDocument`, which evens out a
photographed page the way a scanner's lamp would and is no more a look than
flattening transparency is. No exposure, contrast, curves, LUTs or film looks: that is
[VideoGrade](https://github.com/arraypress/swift-video-grade), which is a
`CGImage → CGImage` engine and composes at exactly the seam this pipeline
works in. Nor reading text: `scan` makes the page, and
[DocumentReader](https://github.com/arraypress/swift-document-reader) reads it
— `writePDF` takes the lines it found. Nor anything with a model behind it — background removal, upscaling,
inpainting and description are their own libraries. This one is the
deterministic transform pipeline, and it stops there.

## Requirements

macOS 26+ / iOS 26+, Swift 6.2 (Xcode 26).

The floor is VideoGrade's (macOS 26), which grading needs. Before that, the HDR gain-map encode
keys (`kCGImageDestinationPreserveGainMap`, `EncodeToISOHDR`) and the
Swift-native Vision request API set it at macOS 15.

## License

MIT — see LICENSE.
