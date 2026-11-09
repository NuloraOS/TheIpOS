Nelora 0.4.0 — two cameras and Dock for iOS 12 / Chimera.

- Classic camera: black-and-white interface, separate Photo/Video modes, larger buttons, digital zoom up to 100x and pinch zoom.
- Bounded GPU preview queue, shared Core Image context, reduced preview render target, no timer-driven layout animations. This is an optimization, not a physical-device FPS guarantee.
- Gallery: three-column cached thumbnails, Photo/Video filters, zoomable photos, video player, sharing and export to Photos.
- Separate Nelora O2 Demo app: orange/red controls, mode strip, zoom dial up to 120x, manual ISO/shutter/exposure/focus/white balance. Real rear recording targets 1080p/30; 4K/60 labels and portrait aperture are demonstration UI only. No proprietary APK/assets are included.
- Dock: backdrop fallback across iOS12 view variants, floating rounded panel, five slots and independent preferences.
- Glass and system Motion removed from new package indexes. Camera/Dock declare conflicts with these retired packages so Sileo can show their removal in its confirmation queue. Manual respring is still required.
- Automated 320x568 UIKit checks and synthetic 1080x1920/30 video check on simulator. Physical camera performance and SpringBoard appearance still require device tests.
