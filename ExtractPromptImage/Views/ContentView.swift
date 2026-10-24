import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var results: [ExtractionResult] = []
    @State private var selection: ExtractionResult.ID?
    @State private var isDropTargeted = false
    @State private var isProcessing = false

    private var selectedResult: ExtractionResult? {
        guard let selection else { return results.first }
        return results.first(where: { $0.id == selection }) ?? results.first
    }

    var body: some View {
        ZStack {
            background

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 260)

                Divider()
                    .background(Theme.separator)

                detailPane
            }
        }
        .preferredColorScheme(nil)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onReceive(NotificationCenter.default.publisher(for: .openImagePicker)) { _ in
            openFiles()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: openFiles) {
                    Label("Open", systemImage: "folder")
                }
                .help("Open image files")

                if let selectedResult, selectedResult.hasPrompt {
                    Button {
                        copyText(selectedResult.displayPrompt)
                    } label: {
                        Label("Copy Prompt", systemImage: "doc.on.doc")
                    }
                    .help("Copy prompt to clipboard")
                }
            }
        }
    }

    private var background: some View {
        Theme.backgroundGradient(for: colorScheme)
            .ignoresSafeArea()
            .overlay {
                GeometryReader { geo in
                    Circle()
                        .fill(Theme.glowPrimary(for: colorScheme))
                        .frame(width: 420, height: 420)
                        .blur(radius: 80)
                        .offset(x: geo.size.width - 280, y: -80)
                    Circle()
                        .fill(Theme.glowSecondary(for: colorScheme))
                        .frame(width: 320, height: 320)
                        .blur(radius: 70)
                        .offset(x: -60, y: geo.size.height - 220)
                }
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.25), value: colorScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extract Prompt")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("Drop AI images to recover prompts")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)

            dropZone
                .padding(.horizontal, 14)

            if results.isEmpty {
                Spacer()
                emptySidebarHint
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(results) { result in
                        FileRow(result: result)
                            .tag(result.id)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.sidebarBackground)
    }

    private var dropZone: some View {
        Button(action: openFiles) {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text(isDropTargeted ? "Release to extract" : "Drop images here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text("PNG · JPEG · WebP · TIFF · HEIC")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted ? Theme.panelFillStrong : Theme.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Theme.accent.opacity(isDropTargeted ? 0.85 : 0.35),
                                style: StrokeStyle(lineWidth: 1.2, dash: isDropTargeted ? [] : [6, 5])
                            )
                    )
            )
            .scaleEffect(isDropTargeted ? 1.02 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isDropTargeted)
        }
        .buttonStyle(.plain)
    }

    private var emptySidebarHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Theme.quaternaryText)
            Text("Supports A1111, ComfyUI,\nNovelAI, InvokeAI & EXIF")
                .multilineTextAlignment(.center)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let result = selectedResult {
            ResultDetailView(result: result, onCopy: copyText)
                .id(result.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            VStack(spacing: 14) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Reading metadata…")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(Theme.quaternaryText)
                        .symbolEffect(.pulse, options: .repeating, isActive: isDropTargeted)
                    Text("Open or drop an image to begin")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text("Embedded generation prompts will appear here")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .png, .jpeg, .webP, .tiff, .heic, .gif, .image
        ]
        panel.begin { response in
            guard response == .OK else { return }
            ingest(urls: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                } else if let url = item as? URL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            ingest(urls: urls)
        }
        return true
    }

    private func ingest(urls: [URL]) {
        let imageURLs = urls.filter { PromptExtractor.isSupported($0) }
        guard !imageURLs.isEmpty else { return }

        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let extracted = imageURLs.map { PromptExtractor.extract(from: $0) }
            DispatchQueue.main.async {
                let existing = Set(results.map(\.fileURL.path))
                let fresh = extracted.filter { !existing.contains($0.fileURL.path) }
                results.insert(contentsOf: fresh, at: 0)
                selection = fresh.first?.id ?? extracted.first?.id
                isProcessing = false
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct FileRow: View {
    let result: ExtractionResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.hasPrompt ? result.source.symbolName : "exclamationmark.triangle")
                .foregroundStyle(result.hasPrompt ? Theme.accent : Color.orange.opacity(0.85))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Theme.primaryText)
                Text(result.hasPrompt ? result.source.rawValue : (result.errorMessage ?? "No prompt"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
