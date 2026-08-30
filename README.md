# Nayar Dental — practice website

A single-file, production-ready website for the dental practice of
**Dr. Sanjna Nayar** (BDS; MDS Prosthodontics & Implantology; PhD Dental
Implantology), New Delhi.

Everything is in `index.html`: markup, styles and behaviour. There is no build
step and no dependencies beyond two Google Fonts. Serve the file over HTTP and
it works.

```bash
python3 -m http.server 8000     # then open http://localhost:8000
```

## What's in it

| Section | Behaviour |
|---|---|
| Hero | ~320vh scroll timeline driving a sticky, viewport-sized stage. On desktop the background film is **scrubbed by scroll position** (interpolated, so it lags the scroll slightly and reverses naturally). Headline lines drift at different rates and leave through a soft diagonal mask; an identity plate emerges behind them; an ivory veil closes the sequence into the section below. |
| Introduction | Word-by-word line-clipped reveal. |
| Treatments | Editorial list, not cards. Rows expand in place; on pointer devices a still follows the cursor. |
| Clinic experience | Full-bleed image with slow scroll parallax. |
| Technology | Large-numeral editorial composition on graphite. |
| Before & after | Draggable comparison with pointer, touch **and** keyboard control. |
| The practice | Dr. Nayar's credentials and biography. |
| Patient stories | Opacity / blur / offset transitions, no auto-advance. |
| Appointment | Validated form with an in-page confirmation state. No browser dialogs. |
| Contact & footer | Address, hours, map, directions, tap-to-call and WhatsApp on mobile. |

## Customising

**One place for the things you'll change most.** Near the top of the `<script>`
at the foot of `index.html`:

```js
var CONFIG = {
  media: {
    hero: [ { src: '…1080p.mp4', minWidth: 1000 },
            { src: '…720p.mp4',  minWidth: 0 } ],  // first match wins
    portrait: ''                                    // '' → designed placeholder
  },
  clinic: { phone, phoneHref, email, whatsapp },     // rendered into the page
  motion: { heroScrub, followLerp, compareLerp }     // interpolation weights
};
```

Contact details are written into every `[data-clinic]` element, so changing
them here updates the nav, the CTA, the contact block and the footer at once.

**Colour, type and spacing** are CSS custom properties in `:root` — palette,
type scale, gutters, section rhythm, easing curves and durations.

**Section content** is plain semantic HTML; each section is commented.

## Before launch — replace these

Everything below is deliberately marked as placeholder, in the code and (where
a visitor could otherwise be misled) on the page itself:

- **Contact details.** `+91 11 4000 0000` and `appointments@nayardental.example`
  are placeholders. `.example` is a reserved documentation domain.
- **Patient stories.** Illustrative copy with initials only. Replace with real,
  consented feedback and remove the note in the section footer.
- **Before & after.** Both layers are currently the *same* stock photograph;
  the "before" side is a CSS grade, not a clinical record. Replace with the
  practice's own consented case photography and remove the caption.
- **Portrait.** No stock face stands in for Dr. Nayar. Set
  `CONFIG.media.portrait` to a real photograph; until then a designed plate
  with her monogram is shown.
- **Hero footage and photography.** Currently Pexels / Unsplash placeholders.
  Check licensing, or better, shoot the clinic.
- **Social links and Privacy / Terms** point at `#`.

Dr. Nayar's name, qualifications, registration number (DCI-3083), languages,
years in practice and consulting location are taken from her public
Apollo 247 profile. Verify them with her before publishing.

## Notes on behaviour

- **Video.** Scrubbing runs on desktop only; on touch the film simply plays,
  which is smoother and kinder to the battery. If the footage cannot load,
  cannot be decoded, or reports a non-finite duration, the hero switches to a
  **still-frame sequence cross-faded on the same timeline** — the choreography
  is identical either way. A failed image likewise leaves a designed surface
  rather than a hole.
- **Performance.** One `requestAnimationFrame` loop drives every scroll-linked
  value. Scroll position is read once per frame, element geometry is measured
  only on resize, and the loop sleeps when the page is idle. Scroll listeners
  are passive; below-the-fold images are lazy-loaded.
- **Accessibility.** Semantic landmarks, a skip link, visible focus on
  everything focusable, real buttons and links, labelled form fields with
  `aria-live` errors, a keyboard-operable comparison slider, and collapsed
  panels that leave the tab order. `prefers-reduced-motion: reduce` collapses
  the hero timeline and replaces the cinematic layer with simple fades.
- **Browser support.** Current Chrome, Safari, Firefox and Edge. Uses
  `clip-path`, `mask-image`, `overflow: clip`, `aspect-ratio` and
  `grid-template-rows` animation.

## Verified

Checked in headless Chromium at 390 / 768 / 900 / 1100 / 1512px: no console
errors, no horizontal overflow at any width, hero scrub tracking and reversing
with scroll, still-frame fallback, treatment expansion, comparison drag and
keyboard control, story navigation, form validation and success state, mobile
menu open / Escape / link-close, tab order, and the reduced-motion path.
