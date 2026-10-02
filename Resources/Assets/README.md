# Application icon

`JiukongZhuyin.png` is the original image supplied by the project owner from
the 久空 workspace (`久空輸入法/久空輸入法.png`). Its artwork and background
are preserved in the application icon.

Run `bash scripts/generate-app-icon.sh` from the repository root on macOS to
generate `JiukongZhuyin.icns` (16–1024 pixel representations) and
`JiukongZhuyin.tiff` (128 pixels). These are already referenced by the Xcode
project and Info.plist. The PNG replaces the previous SVG source.

`JiukongMenuIcon.tiff` is the Chinese input mode's menu-bar icon (16 pt with
a Retina representation). The same script renders it from the PNG with
`scripts/render-menu-icon.swift`, which clears the black backdrop around the
mark and crops the mark to a square so it stays legible at menu-bar size.

The English mode keeps the blue A asset `JiukongEnglishAColor.tiff`. The red
中 asset `JiukongChineseColor.tiff` that the Chinese mode used before is kept
here but is no longer bundled.
