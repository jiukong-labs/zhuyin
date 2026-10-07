# Application icon

`JiukongZhuyin.png` is the original image supplied by the project owner from
the 久空 workspace (`久空輸入法/久空輸入法.png`). Its artwork and background
are preserved in the application icon.

Run `bash scripts/generate-app-icon.sh` from the repository root on macOS to
generate `JiukongZhuyin.icns` (16–1024 pixel representations) and
`JiukongZhuyin.tiff` (128 pixels). These are already referenced by the Xcode
project and Info.plist. The PNG replaces the previous SVG source.

`JiukongMenuIcon.tiff` is the menu-bar icon of the 久空 input mode,
which the "switch only within Jiukong" Shift style selects for Chinese (16 pt
with a Retina representation). The same script renders it from
`JiukongMenuArtwork.png`, supplied by the project owner from
`久空輸入法/久空輸入法去背.png`, with `scripts/render-menu-icon.swift`.
The renderer preserves the original colors and alpha and crops transparent
margins to a centered square. `TISIconIsTemplate` is explicitly false on
each input mode as well as the parent input method, so mode icons retain
their colors instead of tinting the opaque artwork into a solid silhouette.

The Chinese and English modes keep the separate red 中 and blue A assets,
`JiukongChineseColor.tiff` and `JiukongEnglishAColor.tiff`.
