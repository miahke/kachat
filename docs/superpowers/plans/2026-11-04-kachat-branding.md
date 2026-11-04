# kachat branding implementation plan

Goal: use the approved direct photo-to-symbols artwork as the Android icon,
rename the Android/Flutter app to kachat, and provide system-theme icon support.
The photo proportions, facial features and watch remain unchanged.

- [x] Retain approved SVG/text as editable artwork and render green/transparent
  foreground/white-on-transparent monochrome assets without image generation.
- [x] Replace legacy mipmaps and adaptive foregrounds; add API33 monochrome
  resource with matching inset and launcher configuration for regeneration.
- [x] Rename launcher/app titles, modified About notice and qWDTT notification.
  Preserve upstream attribution, package ID, protocol strings and backend URLs.
- [x] Verify image sizes/alpha, XML resource references and themed-mask previews;
  analyze the changed Dart files. Do not build APK until user approval.

Verification: unchanged approved SVG bytes; all mipmap/drawable dimensions and
transparent monochrome alpha checked; AAPT2 resource compilation and Dart
analysis passed. No APK was assembled or installed for this branding patch.
