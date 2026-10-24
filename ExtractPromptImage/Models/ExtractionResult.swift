import Foundation

struct ExtractionResult: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let source: PromptSource
    let prompt: String?
    let negativePrompt: String?
    let systemPrompt: String?
    let parameters: [ParameterEntry]
    let rawText: String?
    let workflowJSON: String?
    let allFields: [MetadataField]
    let errorMessage: String?

    var hasPrompt: Bool {
        !(prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var displayPrompt: String {
        prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    init(
        id: UUID = UUID(),
        fileURL: URL,
        fileName: String,
        source: PromptSource,
        prompt: String? = nil,
        negativePrompt: String? = nil,
        systemPrompt: String? = nil,
        parameters: [ParameterEntry] = [],
        rawText: String? = nil,
        workflowJSON: String? = nil,
        allFields: [MetadataField] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName
        self.source = source
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.systemPrompt = systemPrompt
        self.parameters = parameters
        self.rawText = rawText
        self.workflowJSON = workflowJSON
        self.allFields = allFields
        self.errorMessage = errorMessage
    }
}

enum PromptSource: String, Equatable {
    case automatic1111 = "Stable Diffusion / A1111"
    case comfyUI = "ComfyUI"
    case novelAI = "NovelAI"
    case invokeAI = "InvokeAI"
    case exif = "EXIF / IPTC"
    case pngText = "PNG Text"
    case xmp = "XMP"
    case unknown = "Unknown"
    case none = "No prompt found"

    var symbolName: String {
        switch self {
        case .automatic1111: return "sparkles"
        case .comfyUI: return "point.3.connected.trianglepath.dotted"
        case .novelAI: return "book.closed"
        case .invokeAI: return "wand.and.stars"
        case .exif, .pngText, .xmp: return "doc.text"
        case .unknown: return "questionmark.circle"
        case .none: return "slash.circle"
        }
    }
}

struct ParameterEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let key: String
    let value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct MetadataField: Identifiable, Equatable, Hashable {
    let id: UUID
    let key: String
    let value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
