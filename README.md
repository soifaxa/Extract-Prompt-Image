# Extract Prompt Image

Native macOS app that extracts AI generation prompts from image metadata.

## Features

- Drag & drop or open PNG, JPEG, WebP, TIFF, HEIC, GIF
- Supports **Automatic1111 / Stable Diffusion**, **ComfyUI**, **NovelAI**, **InvokeAI**, and EXIF / IPTC text
- Shows positive & negative prompts, generation parameters, raw metadata
- Copy prompt to clipboard (`⌘C` via Copy Prompt)

## Requirements

- macOS 14+
- Xcode 16+

## Build & run

```bash
xcodegen generate
open ExtractPromptImage.xcodeproj
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme ExtractPromptImage -configuration Debug build
```

Then launch the app from DerivedData, or run from Xcode (`⌘R`).

## Supported metadata

| Source | Where it lives |
|--------|----------------|
| A1111 / Forge | PNG `parameters` tEXt chunk |
| ComfyUI | PNG `prompt` / `workflow` JSON |
| NovelAI | PNG `Comment` |
| InvokeAI | PNG `invokeai` / `sd-metadata` |
| EXIF | UserComment, ImageDescription, Caption |
