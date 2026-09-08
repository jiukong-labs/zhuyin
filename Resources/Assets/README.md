# Application icon

`JiukongZhuyin.png` is the original image supplied by the project owner from
the 久空 workspace (`久空輸入法/久空輸入法.png`). Its artwork and background
are preserved when generating the macOS resources.

Run `bash scripts/generate-app-icon.sh` from the repository root on macOS to
generate `JiukongZhuyin.icns` (16–1024 pixel representations) and
`JiukongZhuyin.tiff` (128 pixels). These are already referenced by the Xcode
project and Info.plist. The PNG replaces the previous SVG source.

The Chinese and English mode icons remain the separate red 中 and blue A
assets used by the input menu.
