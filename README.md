# F75 GIF Uploader

Tiny macOS uploader for the Aula F75 Max 128 x 128 screen.

It keeps the flow intentionally small:

1. Double-click the app.
2. Drop or choose an image/GIF.
3. The app checks dimensions and frame count.
4. Press **Send to F75 Max**.
5. Watch the progress bar finish.

The app bundles the independently reverse-engineered `F75Probe` helper from
`RoseWaveStudio/Aula-F75-Max-OSX` and calls it for the actual HID upload. This
project is not affiliated with Aula, Epomaker, or the official Windows driver.

## Safety Checks

- Accepts GIF, PNG, JPG, and JPEG files.
- Checks the first frame dimensions.
- Allows up to 120 frames by default.
- Uses the proven F75 Max wired screen upload path.
- Resizes/crops to the keyboard's 128 x 128 target through the helper.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac recommended
- Aula F75 Max in wired USB mode
- Input Monitoring permission if macOS requests it

## Build

```sh
make all
open build/F75GifUploader.app
```

## Notes

Screen upload requires the wired USB device path `0C45:800A` and the HID
endpoints used by the Aula F75 Max. Other F75 variants may not work.
