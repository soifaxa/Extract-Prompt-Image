import SwiftUI
import AppKit

struct ResultDetailView: View {
    let result: ExtractionResult
    let onCopy: (String) -> Void

    @State private var selectedTab: DetailTab = .prompt
    @State private var didCopy = false

    private enum DetailTab: String, CaseIterable, Identifiable {
        case prompt = "Prompt"
        case parameters = "Parameters"
        case raw = "Raw"
        case metadata = "All metadata"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            tabBar
            content
        }
        .padding(24)
        .animation(.easeOut(duration: 0.25), value: result.id)
        .onChange(of: result.id) { _, _ in
            selectedTab = .prompt
            didCopy = false
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnail
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.panelStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(result.fileName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(result.source.rawValue, systemImage: result.source.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.chipBackground, in: Capsule())
                        .foregroundStyle(Theme.accentSoft)

                    if result.hasPrompt {
                        Text("Prompt found")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text(result.errorMessage ?? "No prompt")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                }

                Text(result.fileURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if result.hasPrompt {
                Button {
                    onCopy(result.displayPrompt)
                    withAnimation { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { didCopy = false }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy Prompt", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Theme.accentButton.opacity(didCopy ? 0.9 : 1),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3), value: didCopy)
            }
        }
        .padding(.bottom, 18)
    }

    private var thumbnail: some View {
        AsyncImage(url: result.fileURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholderThumb
            case .empty:
                ProgressView()
            @unknown default:
                placeholderThumb
            }
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            Theme.panelFill
            Image(systemName: "photo")
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(availableTabs) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Theme.primaryText : Theme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab ? Theme.panelFillStrong : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = [.prompt]
        if !result.parameters.isEmpty { tabs.append(.parameters) }
        if result.rawText != nil || result.workflowJSON != nil { tabs.append(.raw) }
        if !result.allFields.isEmpty { tabs.append(.metadata) }
        return tabs
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .prompt:
            promptContent
        case .parameters:
            parametersContent
        case .raw:
            rawContent
        case .metadata:
            metadataContent
        }
    }

    private var promptContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(title: "Positive prompt", text: result.displayPrompt.isEmpty ? "—" : result.displayPrompt, copyable: result.hasPrompt)

                if let negative = result.negativePrompt, !negative.isEmpty {
                    section(title: "Negative prompt", text: negative, copyable: true)
                }

                if let system = result.systemPrompt, !system.isEmpty {
                    section(title: "System prompt", text: system, copyable: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var parametersContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 200), spacing: 10)
            ], spacing: 10) {
                ForEach(result.parameters) { param in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(param.key)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                        Text(param.value)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.primaryText)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 4)
        }
    }

    private var rawContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let workflow = result.workflowJSON {
                    section(title: "Workflow / JSON", text: workflow, copyable: true, mono: true)
                } else if let raw = result.rawText {
                    section(title: "Raw parameters", text: raw, copyable: true, mono: true)
                } else {
                    Text("No raw data")
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.top, 4)
        }
    }

    private var metadataContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(result.allFields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.key)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent.opacity(0.9))
                        Text(field.value)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 4)
        }
    }

    private func section(title: String, text: String, copyable: Bool, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if copyable, text != "—" {
                    Button {
                        onCopy(text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(text)
                .font(mono
                      ? .system(size: 12, design: .monospaced)
                      : .system(size: 14))
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.panelStroke, lineWidth: 1)
                )
        }
    }
}
