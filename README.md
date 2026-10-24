# Extract Prompt Image

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Extract Prompt Image icon">
</p>

Native macOS app that extracts **AI generation prompts** from image metadata.

Drop a PNG (or JPEG / WebP / …) produced by Stable Diffusion, ComfyUI, NovelAI, or similar tools, and recover the positive prompt, negative prompt, and generation parameters.

## Features

- Drag & drop or open **PNG, JPEG, WebP, TIFF, HEIC, GIF**
- Supports **Automatic1111 / Forge**, **ComfyUI** (including custom nodes such as `prompt` / `system_prompt`), **NovelAI**, **InvokeAI**, and EXIF / IPTC text
- Shows positive & negative prompts, system prompt, size & parameters
- Raw workflow JSON and full metadata tabs
- Copy prompt to clipboard
- Follows system **Light / Dark** appearance

## Requirements

- macOS 14 or later  
- No account, no network — metadata is read locally  

## Install (release)

Download the latest `.app` from the [Releases](https://github.com/soifaxa/Extract-Prompt-Image/releases) page:

1. Download **ExtractPromptImage-*-macos.zip**
2. Unzip and move `Extract Prompt Image.app` to `/Applications`
3. Open the app (right-click → **Open** if Gatekeeper blocks it — the release is ad-hoc signed, not notarized)

```bash
# Example for v1.0.0
curl -L -o ExtractPromptImage.zip \
  https://github.com/soifaxa/Extract-Prompt-Image/releases/download/v1.0.0/ExtractPromptImage-1.0.0-macos.zip
unzip ExtractPromptImage.zip
mv "Extract Prompt Image.app" /Applications/
open "/Applications/Extract Prompt Image.app"
```

## Usage

1. Drop one or more images onto the drop zone (or **Open** / `⌘O`)
2. Select a file in the sidebar
3. Read the **Prompt** tab; use **Parameters**, **Raw**, and **All metadata** as needed
4. Click **Copy Prompt** to copy the positive prompt

More detail: [Wiki → Usage](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Usage)

## Supported metadata

| Source | Where it lives |
|--------|----------------|
| A1111 / Forge | PNG `parameters` tEXt chunk |
| ComfyUI | PNG `prompt` / `workflow` JSON |
| NovelAI | PNG `Comment` |
| InvokeAI | PNG `invokeai` / `sd-metadata` |
| EXIF / IPTC | UserComment, ImageDescription, Caption |

## Build from source

```bash
brew install xcodegen   # if needed
xcodegen generate
open ExtractPromptImage.xcodeproj
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme ExtractPromptImage -configuration Release -derivedDataPath build/release build
```

See [Building from Source](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Building-from-Source).

## Documentation

Full docs live in the [Wiki](https://github.com/soifaxa/Extract-Prompt-Image/wiki):

| Page | Description |
|------|-------------|
| [Installation](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Installation) | Download and install from Releases |
| [Usage](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Usage) | Drop zone, tabs, copy |
| [Supported Formats](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Supported-Formats) | Metadata sources in detail |
| [Building from Source](https://github.com/soifaxa/Extract-Prompt-Image/wiki/Building-from-Source) | XcodeGen + xcodebuild |
| [FAQ](https://github.com/soifaxa/Extract-Prompt-Image/wiki/FAQ) | Common questions |

## Notes

- Releases are **ad-hoc signed**, not notarized — use right-click → **Open** the first time, or clear quarantine with `xattr`.
- The app only reads user-selected / dropped files (App Sandbox).
- Midjourney and some web exports often strip metadata; if nothing is found, the file likely has no embedded prompt.
