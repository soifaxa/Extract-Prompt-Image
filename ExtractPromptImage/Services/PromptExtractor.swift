import Foundation
import ImageIO
import UniformTypeIdentifiers
import Compression

enum PromptExtractor {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "tif", "tiff", "heic", "gif"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func extract(from url: URL) -> ExtractionResult {
        let fileName = url.lastPathComponent
        guard isSupported(url) else {
            return ExtractionResult(
                fileURL: url,
                fileName: fileName,
                source: .none,
                errorMessage: "Unsupported file type."
            )
        }

        do {
            let data = try Data(contentsOf: url)
            var fields: [MetadataField] = []

            let pngTexts = extractPNGTextChunks(from: data)
            fields.append(contentsOf: pngTexts.map { MetadataField(key: "PNG:\($0.key)", value: $0.value) })

            let imageIOFields = extractImageIOMetadata(from: url)
            fields.append(contentsOf: imageIOFields)

            if let result = parseKnownFormats(
                fileURL: url,
                fileName: fileName,
                pngTexts: pngTexts,
                imageIOFields: imageIOFields,
                allFields: fields
            ) {
                return withEnsuredSize(result)
            }

            if let fallback = firstInterestingText(from: fields) {
                let parsed = parseA1111Parameters(fallback.value)
                return withEnsuredSize(ExtractionResult(
                    fileURL: url,
                    fileName: fileName,
                    source: .pngText,
                    prompt: parsed.prompt ?? fallback.value,
                    negativePrompt: parsed.negativePrompt,
                    parameters: parsed.parameters,
                    rawText: fallback.value,
                    allFields: fields
                ))
            }

            return withEnsuredSize(ExtractionResult(
                fileURL: url,
                fileName: fileName,
                source: .none,
                allFields: fields,
                errorMessage: fields.isEmpty
                    ? "No metadata found in this image."
                    : "Metadata found, but no recognizable prompt."
            ))
        } catch {
            return ExtractionResult(
                fileURL: url,
                fileName: fileName,
                source: .none,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Format routing

    private static func parseKnownFormats(
        fileURL: URL,
        fileName: String,
        pngTexts: [(key: String, value: String)],
        imageIOFields: [MetadataField],
        allFields: [MetadataField]
    ) -> ExtractionResult? {
        var textMap: [String: String] = [:]
        for pair in pngTexts {
            textMap[pair.key.lowercased()] = pair.value
        }

        if let parameters = textMap["parameters"], looksLikeA1111(parameters) {
            let parsed = parseA1111Parameters(parameters)
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .automatic1111,
                prompt: parsed.prompt,
                negativePrompt: parsed.negativePrompt,
                parameters: parsed.parameters,
                rawText: parameters,
                allFields: allFields
            )
        }

        if let promptJSON = textMap["prompt"], looksLikeJSON(promptJSON), looksLikeComfyGraph(promptJSON) {
            let prompts = extractComfyUIPrompts(from: promptJSON)
            let pretty = prettyPrintedJSON(promptJSON) ?? promptJSON
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .comfyUI,
                prompt: prompts.positive.isEmpty ? nil : prompts.positive.joined(separator: "\n\n"),
                negativePrompt: prompts.negative.isEmpty ? nil : prompts.negative.joined(separator: "\n\n"),
                systemPrompt: prompts.system.isEmpty ? nil : prompts.system.joined(separator: "\n\n"),
                parameters: prompts.parameters,
                rawText: promptJSON,
                workflowJSON: pretty,
                allFields: allFields
            )
        }

        if let workflow = textMap["workflow"], looksLikeJSON(workflow) {
            let prompts = extractComfyUIPrompts(from: workflow)
            let pretty = prettyPrintedJSON(workflow) ?? workflow
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .comfyUI,
                prompt: prompts.positive.isEmpty ? nil : prompts.positive.joined(separator: "\n\n"),
                negativePrompt: prompts.negative.isEmpty ? nil : prompts.negative.joined(separator: "\n\n"),
                systemPrompt: prompts.system.isEmpty ? nil : prompts.system.joined(separator: "\n\n"),
                parameters: prompts.parameters,
                rawText: workflow,
                workflowJSON: pretty,
                allFields: allFields
            )
        }

        if let comment = textMap["comment"], looksLikeNovelAI(comment) {
            let parsed = parseNovelAIComment(comment)
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .novelAI,
                prompt: parsed.prompt,
                negativePrompt: parsed.negativePrompt,
                parameters: parsed.parameters,
                rawText: comment,
                allFields: allFields
            )
        }

        if let invoke = textMap["invokeai"] ?? textMap["invokeai_metadata"] ?? textMap["sd-metadata"] {
            let parsed = parseInvokeOrSDMetadata(invoke)
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .invokeAI,
                prompt: parsed.prompt,
                negativePrompt: parsed.negativePrompt,
                parameters: parsed.parameters,
                rawText: invoke,
                allFields: allFields
            )
        }

        if let prompt = textMap["prompt"], !looksLikeJSON(prompt) {
            return ExtractionResult(
                fileURL: fileURL,
                fileName: fileName,
                source: .pngText,
                prompt: prompt,
                rawText: prompt,
                allFields: allFields
            )
        }

        for field in imageIOFields {
            let key = field.key.lowercased()
            let value = field.value
            if key.contains("usercomment") || key.contains("imagedescription") || key.contains("caption") {
                if looksLikeA1111(value) {
                    let parsed = parseA1111Parameters(value)
                    return ExtractionResult(
                        fileURL: fileURL,
                        fileName: fileName,
                        source: .exif,
                        prompt: parsed.prompt,
                        negativePrompt: parsed.negativePrompt,
                        parameters: parsed.parameters,
                        rawText: value,
                        allFields: allFields
                    )
                }
                if value.count > 8, !value.hasPrefix("{") {
                    return ExtractionResult(
                        fileURL: fileURL,
                        fileName: fileName,
                        source: .exif,
                        prompt: value,
                        rawText: value,
                        allFields: allFields
                    )
                }
            }
        }

        return nil
    }

    // MARK: - PNG text chunks

    private static func extractPNGTextChunks(from data: Data) -> [(key: String, value: String)] {
        guard data.count >= 8 else { return [] }
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.prefix(8) == signature else { return [] }

        var results: [(key: String, value: String)] = []
        var offset = 8

        while offset + 12 <= data.count {
            let length = Int(readUInt32BE(data, offset))
            offset += 4
            guard offset + 4 + length + 4 <= data.count else { break }

            let typeData = data.subdata(in: offset..<(offset + 4))
            let type = String(data: typeData, encoding: .ascii) ?? ""
            offset += 4
            let chunkData = data.subdata(in: offset..<(offset + length))
            offset += length
            offset += 4 // CRC

            switch type {
            case "tEXt":
                if let pair = parseTEXt(chunkData) {
                    results.append(pair)
                }
            case "iTXt":
                if let pair = parseITXt(chunkData) {
                    results.append(pair)
                }
            case "zTXt":
                if let pair = parseZTXt(chunkData) {
                    results.append(pair)
                }
            case "IEND":
                return results
            default:
                continue
            }
        }

        return results
    }

    private static func parseTEXt(_ data: Data) -> (key: String, value: String)? {
        guard let nullIndex = data.firstIndex(of: 0) else { return nil }
        let keyData = data.subdata(in: data.startIndex..<nullIndex)
        let valueData = data.subdata(in: data.index(after: nullIndex)..<data.endIndex)
        guard let key = String(data: keyData, encoding: .isoLatin1),
              let value = String(data: valueData, encoding: .isoLatin1) ?? String(data: valueData, encoding: .utf8)
        else { return nil }
        return (key, sanitizeText(value))
    }

    private static func parseZTXt(_ data: Data) -> (key: String, value: String)? {
        guard let nullIndex = data.firstIndex(of: 0) else { return nil }
        let keyData = data.subdata(in: data.startIndex..<nullIndex)
        let afterKey = data.index(after: nullIndex)
        guard afterKey < data.endIndex else { return nil }
        // compression method byte
        let compressedStart = data.index(after: afterKey)
        guard compressedStart < data.endIndex else { return nil }
        let compressed = data.subdata(in: compressedStart..<data.endIndex)
        guard let key = String(data: keyData, encoding: .isoLatin1),
              let inflated = inflateZlib(compressed),
              let value = String(data: inflated, encoding: .isoLatin1) ?? String(data: inflated, encoding: .utf8)
        else { return nil }
        return (key, sanitizeText(value))
    }

    private static func parseITXt(_ data: Data) -> (key: String, value: String)? {
        guard let keyNull = data.firstIndex(of: 0) else { return nil }
        let keyData = data.subdata(in: data.startIndex..<keyNull)
        var index = data.index(after: keyNull)
        guard index < data.endIndex else { return nil }
        let compressionFlag = data[index]
        index = data.index(after: index)
        guard index < data.endIndex else { return nil }
        // compression method
        index = data.index(after: index)

        // language tag
        guard let langNull = data[index...].firstIndex(of: 0) else { return nil }
        index = data.index(after: langNull)
        // translated keyword
        guard let transNull = data[index...].firstIndex(of: 0) else { return nil }
        index = data.index(after: transNull)
        guard index <= data.endIndex else { return nil }

        let textData = data.subdata(in: index..<data.endIndex)
        let decoded: Data?
        if compressionFlag == 1 {
            decoded = inflateZlib(textData)
        } else {
            decoded = textData
        }

        guard let key = String(data: keyData, encoding: .utf8) ?? String(data: keyData, encoding: .isoLatin1),
              let bytes = decoded,
              let value = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
        else { return nil }
        return (key, sanitizeText(value))
    }

    // MARK: - ImageIO metadata

    private static func extractImageIOMetadata(from url: URL) -> [MetadataField] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }

        var fields: [MetadataField] = []
        flattenMetadata(properties, prefix: "", into: &fields)
        return fields
    }

    private static func flattenMetadata(_ dictionary: [String: Any], prefix: String, into fields: inout [MetadataField]) {
        for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                flattenMetadata(nested, prefix: path, into: &fields)
            } else if let array = value as? [Any] {
                let joined = array.map { String(describing: $0) }.joined(separator: ", ")
                if !joined.isEmpty {
                    fields.append(MetadataField(key: path, value: sanitizeText(joined)))
                }
            } else {
                let text = sanitizeText(String(describing: value))
                if !text.isEmpty, text != "<null>" {
                    fields.append(MetadataField(key: path, value: text))
                }
            }
        }
    }

    // MARK: - Parsers

    private static func looksLikeA1111(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("negative prompt:")
            || lower.contains("\nsteps:")
            || lower.contains("sampler:")
            || lower.contains("cfg scale:")
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private static func looksLikeNovelAI(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("\"steps\"") && (lower.contains("\"sm\"") || lower.contains("novelai") || lower.contains("\"uc\""))
    }

    private static func parseA1111Parameters(_ text: String) -> (prompt: String?, negativePrompt: String?, parameters: [ParameterEntry]) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var prompt: String?
        var negative: String?
        var parameters: [ParameterEntry] = []

        if let negRange = normalized.range(of: "\nNegative prompt:", options: .caseInsensitive) {
            prompt = String(normalized[..<negRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let afterNeg = normalized[negRange.upperBound...]
            if let stepsRange = afterNeg.range(of: "\nSteps:", options: .caseInsensitive) {
                negative = String(afterNeg[..<stepsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let paramLine = String(afterNeg[stepsRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                parameters = parseParameterLine(paramLine)
            } else {
                negative = String(afterNeg).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let stepsRange = normalized.range(of: "\nSteps:", options: .caseInsensitive) {
            prompt = String(normalized[..<stepsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let paramLine = String(normalized[stepsRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            parameters = parseParameterLine(paramLine)
        } else {
            prompt = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (emptyToNil(prompt), emptyToNil(negative), parameters)
    }

    private static func parseParameterLine(_ line: String) -> [ParameterEntry] {
        // Split on commas that separate key: value pairs, keeping commas inside values when possible.
        var entries: [ParameterEntry] = []
        let parts = splitParameterPairs(line)
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                entries.append(ParameterEntry(key: key, value: value))
            }
        }
        return entries
    }

    private static func splitParameterPairs(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in line {
            if character == "(" || character == "[" || character == "{" {
                depth += 1
                current.append(character)
            } else if character == ")" || character == "]" || character == "}" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character == "," && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts
    }

    private static func looksLikeComfyGraph(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("\"class_type\"")
            || lower.contains("\"nodes\"")
            || lower.contains("\"widgets_values\"")
            || (lower.contains("\"inputs\"") && lower.contains("\"unetloader\""))
            || (lower.contains("\"inputs\"") && lower.contains("\"cliploader\""))
            || (lower.contains("\"inputs\"") && lower.contains("\"ksampler\""))
    }

    private static func extractComfyUIPrompts(from jsonText: String) -> (positive: [String], negative: [String], system: [String], parameters: [ParameterEntry]) {
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return ([], [], [], []) }

        var positives: [String] = []
        var negatives: [String] = []
        var systems: [String] = []
        var parameters: [ParameterEntry] = []
        var seenPositive = Set<String>()
        var seenNegative = Set<String>()
        var seenSystem = Set<String>()

        let positiveKeys = ["prompt", "text", "positive", "positive_prompt", "text_g", "text_l"]
        let negativeKeys = ["negative", "negative_prompt", "uc", "text_negative"]
        let systemKeys = ["system_prompt", "system", "systemprompt"]
        let samplerKeys = ["seed", "steps", "cfg", "cfg_scale", "sampler_name", "scheduler", "denoise", "noise_seed"]
        var graphWidth: Int?
        var graphHeight: Int?

        func appendUnique(_ value: String, into list: inout [String], seen: inout Set<String>) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !looksLikeJSON(trimmed), seen.insert(trimmed).inserted else { return }
            list.append(trimmed)
        }

        func intValue(_ value: Any?) -> Int? {
            if let i = value as? Int { return i }
            if let n = value as? NSNumber { return n.intValue }
            if let d = value as? Double { return Int(d) }
            if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }

        func isNegativeContext(classType: String, path: String, key: String) -> Bool {
            let haystack = "\(classType) \(path) \(key)".lowercased()
            return haystack.contains("negative") || haystack.contains("neg_prompt")
        }

        func collectFromInputs(_ inputs: [String: Any], classType: String, path: String) {
            for key in systemKeys {
                if let text = inputs[key] as? String {
                    appendUnique(text, into: &systems, seen: &seenSystem)
                }
            }

            for key in negativeKeys {
                if let text = inputs[key] as? String {
                    appendUnique(text, into: &negatives, seen: &seenNegative)
                }
            }

            for key in positiveKeys {
                guard let text = inputs[key] as? String else { continue }
                if isNegativeContext(classType: classType, path: path, key: key) {
                    appendUnique(text, into: &negatives, seen: &seenNegative)
                } else {
                    appendUnique(text, into: &positives, seen: &seenPositive)
                }
            }

            let lowerClass = classType.lowercased()
            if lowerClass.contains("ksampler") || lowerClass.contains("sampler") {
                for key in samplerKeys {
                    if let value = inputs[key], !(value is [Any]), !(value is [String: Any]) {
                        parameters.append(ParameterEntry(key: key, value: String(describing: value)))
                    }
                }
            }

            // Latent / scale / resize nodes often carry the generation size.
            if let w = intValue(inputs["width"]), let h = intValue(inputs["height"]), w > 0, h > 0 {
                if graphWidth == nil || lowerClass.contains("emptylatent") || lowerClass.contains("imagescale") || lowerClass.contains("resize") {
                    graphWidth = w
                    graphHeight = h
                }
            }
        }

        func walk(_ node: Any, path: String) {
            if let dict = node as? [String: Any] {
                let classType = (dict["class_type"] as? String)
                    ?? (dict["type"] as? String)
                    ?? ""

                if let inputs = dict["inputs"] as? [String: Any] {
                    collectFromInputs(inputs, classType: classType, path: path)
                }

                // ComfyUI UI workflow format stores widget values as an array on the node.
                if let widgets = dict["widgets_values"] as? [Any] {
                    let lowerClass = classType.lowercased()
                    if graphWidth == nil,
                       (lowerClass.contains("emptylatent") || lowerClass.contains("imagescale") || lowerClass.contains("resize")),
                       widgets.count >= 2,
                       let w = intValue(widgets[0]),
                       let h = intValue(widgets[1]),
                       w > 0, h > 0 {
                        graphWidth = w
                        graphHeight = h
                    }

                    for value in widgets {
                        guard let text = value as? String else { continue }
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 12 else { continue }
                        if isNegativeContext(classType: classType, path: path, key: "widgets_values") {
                            appendUnique(trimmed, into: &negatives, seen: &seenNegative)
                        } else if lowerClass.contains("cliptext")
                                    || lowerClass.contains("prompt")
                                    || lowerClass.contains("encode") {
                            appendUnique(trimmed, into: &positives, seen: &seenPositive)
                        }
                    }
                }

                for (key, value) in dict {
                    // Avoid re-walking huge binary/base64 blobs.
                    if key == "png" || key == "image" { continue }
                    walk(value, path: path.isEmpty ? key : "\(path).\(key)")
                }
            } else if let array = node as? [Any] {
                for (index, value) in array.enumerated() {
                    walk(value, path: "\(path)[\(index)]")
                }
            }
        }

        walk(root, path: "")

        if let w = graphWidth, let h = graphHeight {
            let sizeValue = "\(w)×\(h)"
            if !parameters.contains(where: { $0.key.caseInsensitiveCompare("Size") == .orderedSame }) {
                parameters.insert(ParameterEntry(key: "Size", value: sizeValue), at: 0)
            }
        }

        return (positives, negatives, systems, parameters)
    }

    // MARK: - Size helpers

    private static func withEnsuredSize(_ result: ExtractionResult) -> ExtractionResult {
        ExtractionResult(
            id: result.id,
            fileURL: result.fileURL,
            fileName: result.fileName,
            source: result.source,
            prompt: result.prompt,
            negativePrompt: result.negativePrompt,
            systemPrompt: result.systemPrompt,
            parameters: ensureSizeParameter(result.parameters, fileURL: result.fileURL),
            rawText: result.rawText,
            workflowJSON: result.workflowJSON,
            allFields: result.allFields,
            errorMessage: result.errorMessage
        )
    }

    private static func ensureSizeParameter(_ parameters: [ParameterEntry], fileURL: URL) -> [ParameterEntry] {
        let hasSize = parameters.contains {
            $0.key.caseInsensitiveCompare("Size") == .orderedSame
                || $0.key.caseInsensitiveCompare("size") == .orderedSame
        }
        if hasSize { return parameters }

        // Prefer explicit width+height already collected from metadata/workflow.
        let width = parameters.first { $0.key.caseInsensitiveCompare("width") == .orderedSame }?.value
        let height = parameters.first { $0.key.caseInsensitiveCompare("height") == .orderedSame }?.value
        if let width, let height, let w = Int(width), let h = Int(height), w > 0, h > 0 {
            var enriched = parameters
            enriched.insert(ParameterEntry(key: "Size", value: "\(w)×\(h)"), at: 0)
            return enriched
        }

        guard let dims = imagePixelSize(from: fileURL) else { return parameters }
        var enriched = parameters
        enriched.insert(ParameterEntry(key: "Size", value: "\(dims.width)×\(dims.height)"), at: 0)
        return enriched
    }

    private static func imagePixelSize(from url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func parseNovelAIComment(_ text: String) -> (prompt: String?, negativePrompt: String?, parameters: [ParameterEntry]) {
        // NovelAI often stores: prompt then JSON comment, or pure JSON.
        if looksLikeJSON(text),
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let prompt = json["prompt"] as? String
            let uc = json["uc"] as? String ?? json["negative_prompt"] as? String
            var parameters: [ParameterEntry] = []
            for key in ["steps", "scale", "sampler", "seed", "width", "height", "sm", "sm_dyn"] {
                if let value = json[key] {
                    parameters.append(ParameterEntry(key: key, value: String(describing: value)))
                }
            }
            return (emptyToNil(prompt), emptyToNil(uc), parameters)
        }

        if let brace = text.firstIndex(of: "{") {
            let prompt = String(text[..<brace]).trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonPart = String(text[brace...])
            let nested = parseNovelAIComment(jsonPart)
            return (emptyToNil(prompt) ?? nested.prompt, nested.negativePrompt, nested.parameters)
        }

        return (emptyToNil(text), nil, [])
    }

    private static func parseInvokeOrSDMetadata(_ text: String) -> (prompt: String?, negativePrompt: String?, parameters: [ParameterEntry]) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            if looksLikeA1111(text) {
                return parseA1111Parameters(text)
            }
            return (emptyToNil(text), nil, [])
        }

        let prompt = (json["prompt"] as? String)
            ?? (json["positive_prompt"] as? String)
            ?? ((json["image"] as? [String: Any])?["prompt"] as? String)

        let negative = (json["negative_prompt"] as? String)
            ?? (json["uc"] as? String)
            ?? ((json["image"] as? [String: Any])?["negative_prompt"] as? String)

        var parameters: [ParameterEntry] = []
        for key in ["seed", "steps", "cfg_scale", "cfgScale", "scheduler", "sampler", "model", "width", "height"] {
            if let value = json[key] {
                parameters.append(ParameterEntry(key: key, value: String(describing: value)))
            } else if let image = json["image"] as? [String: Any], let value = image[key] {
                parameters.append(ParameterEntry(key: key, value: String(describing: value)))
            }
        }

        return (emptyToNil(prompt), emptyToNil(negative), parameters)
    }

    private static func firstInterestingText(from fields: [MetadataField]) -> MetadataField? {
        let priorityKeys = ["parameters", "prompt", "comment", "usercomment", "imagedescription", "caption", "description"]
        for priority in priorityKeys {
            if let match = fields.first(where: {
                $0.key.lowercased().contains(priority)
                    && $0.value.count > 3
                    && !looksLikeComfyGraph($0.value)
            }) {
                return match
            }
        }
        return fields.first(where: {
            $0.value.count > 40
                && !$0.key.lowercased().contains("exif")
                && !looksLikeComfyGraph($0.value)
                && !looksLikeJSON($0.value)
        })
    }

    // MARK: - Helpers

    private static func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    private static func inflateZlib(_ data: Data) -> Data? {
        // PNG zTXt/iTXt use zlib-wrapped deflate. Try Compression framework raw inflate after skipping zlib header.
        if data.count > 2 {
            let raw = data.subdata(in: 2..<(data.count))
            if let inflated = decompress(raw, algorithm: COMPRESSION_ZLIB) {
                return inflated
            }
        }
        return decompress(data, algorithm: COMPRESSION_ZLIB)
    }

    private static func decompress(_ source: Data, algorithm: compression_algorithm) -> Data? {
        guard !source.isEmpty else { return nil }
        let destinationCapacity = max(source.count * 8, 64 * 1024)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
        defer { destinationBuffer.deallocate() }

        let decodedCount = source.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                destinationCapacity,
                base,
                source.count,
                nil,
                algorithm
            )
        }

        guard decodedCount > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decodedCount)
    }

    private static func prettyPrintedJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func sanitizeText(_ text: String) -> String {
        var cleaned = text
        // Strip common EXIF ASCII prefix junk
        if cleaned.hasPrefix("ASCII") {
            cleaned = cleaned.replacingOccurrences(of: "ASCII\0\0\0", with: "")
            cleaned = cleaned.replacingOccurrences(of: "ASCII", with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "\0", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
