//
//  GeminiService.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import Foundation
import UIKit

final class GeminiService {
    static let shared = GeminiService()

    private let apiKeyProvider: GeminiAPIKeyProviding
    private let urlSession: URLSession
    private let model = "gemini-2.5-flash"
    private let endpointBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    init(
        apiKeyProvider: GeminiAPIKeyProviding = DotEnvGeminiAPIKeyProvider(),
        urlSession: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.urlSession = urlSession
    }

    @discardableResult
    func analyze(
        image: UIImage,
        prompt: String = "Describe this image and identify the main visible objects."
    ) async throws -> String {
        guard let apiKey = apiKeyProvider.apiKey(), !apiKey.isEmpty else {
            let message = "GeminiService error: Missing GEMINI_API_KEY. Create a local .env file with GEMINI_API_KEY=YOUR_API_KEY_HERE."
            print(message)
            throw GeminiServiceError.missingAPIKey
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            print("GeminiService error: Could not convert UIImage to JPEG data.")
            throw GeminiServiceError.imageEncodingFailed
        }

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                .init(
                    parts: [
                        .init(text: prompt, inlineData: nil),
                        .init(
                            text: nil,
                            inlineData: .init(
                                mimeType: "image/jpeg",
                                data: jpegData.base64EncodedString()
                            )
                        )
                    ]
                )
            ]
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? "<non-UTF8 Gemini response>"

        guard let httpResponse = response as? HTTPURLResponse else {
            print("Gemini raw response: \(rawResponse)")
            throw GeminiServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            print("Gemini raw response: \(rawResponse)")
            throw GeminiServiceError.requestFailed(statusCode: httpResponse.statusCode, body: rawResponse)
        }

        print("Gemini raw response: \(rawResponse)")
        return rawResponse
    }

    func generateRepairStep(
        image: UIImage,
        userRequest: String
    ) async throws -> RepairStep {
        try await generateRepairStep(
            image: image,
            userRequest: userRequest,
            visionContext: VisionContext(objects: [])
        )
    }

    func generateRepairStep(
        image: UIImage,
        userRequest: String,
        visionContext: VisionContext
    ) async throws -> RepairStep {
        let prompt = try repairStepPrompt(
            userRequest: userRequest,
            visionContext: visionContext
        )
        let rawResponse = try await analyze(image: image, prompt: prompt)
        let modelText = try extractModelText(from: rawResponse)
        return try decodeRepairStep(from: modelText)
    }

    private var endpointURL: URL {
        endpointBaseURL
            .appendingPathComponent(model + ":generateContent")
    }

    private func repairStepPrompt(
        userRequest: String,
        visionContext: VisionContext
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let contextData = try encoder.encode(visionContext)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? #"{"objects":[]}"#
        let allowedActions = RepairInstructionAction.allCases
            .map(\.rawValue)
            .joined(separator: ", ")

        return """
        You are an AR repair assistant. Inspect the image and decide what the user should do next.

        User request:
        \(userRequest)

        Visible objects:
        \(contextJSON)

        Rules:
        - Return only valid JSON.
        - Do not wrap the JSON in Markdown.
        - Do not return 3D coordinates.
        - Identify the most relevant visible objects and return 2D bounding boxes for them.
        - Bounding boxes must be normalized to the portrait image with x/y measured from the top-left corner and values between 0 and 1.
        - Use only these actions: \(allowedActions).
        - Target values must match a visible object id when possible.
        - If the requested object is not visible or the request does not match the image, return a WARNING instruction with target "scene".
        - If the user asks how to open a water bottle and a bottle/cap is visible, use ROTATE_CCW or UNSCREW for the cap.
        - If the task has multiple obvious physical steps, return multiple instructions in order.
        - Keep "voice" short enough to show on a phone screen.

        JSON schema:
        {
          "step": 1,
          "voice": "Short spoken instruction.",
          "objects": [
            {
              "id": "object_id",
              "label": "object name",
              "bounding_box": {
                "x": 0.1,
                "y": 0.2,
                "width": 0.3,
                "height": 0.4
              }
            }
          ],
          "instructions": [
            {
              "action": "CHECK",
              "target": "object_id"
            }
          ]
        }
        """
    }

    private func extractModelText(from rawResponse: String) throws -> String {
        let data = Data(rawResponse.utf8)
        let response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)

        guard let text = response.candidates
            .flatMap({ $0.content.parts })
            .compactMap(\.text)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw GeminiServiceError.missingModelText
        }

        return text
    }

    private func decodeRepairStep(from rawResponse: String) throws -> RepairStep {
        let jsonString = extractJSONObject(from: rawResponse)
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(RepairStep.self, from: data)
    }

    private func extractJSONObject(from text: String) -> String {
        guard
            let startIndex = text.firstIndex(of: "{"),
            let endIndex = text.lastIndex(of: "}"),
            startIndex <= endIndex
        else {
            return text
        }

        return String(text[startIndex...endIndex])
    }
}

protocol GeminiAPIKeyProviding {
    func apiKey() -> String?
}

struct DotEnvGeminiAPIKeyProvider: GeminiAPIKeyProviding {
    private let keyName = "GEMINI_API_KEY"
    private let fileManager: FileManager
    private let bundle: Bundle

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    func apiKey() -> String? {
        if let environmentValue = normalized(ProcessInfo.processInfo.environment[keyName]) {
            return environmentValue
        }

        for url in candidateEnvFileURLs() {
            guard
                fileManager.fileExists(atPath: url.path),
                let contents = try? String(contentsOf: url, encoding: .utf8),
                let value = parse(contents: contents)[keyName],
                let normalizedValue = normalized(value)
            else {
                continue
            }

            return normalizedValue
        }

        return nil
    }

    private func candidateEnvFileURLs() -> [URL] {
        var urls: [URL] = []

        if let directBundleURL = bundle.url(forResource: ".env", withExtension: nil) {
            urls.append(directBundleURL)
        }

        if let resourceURL = bundle.resourceURL {
            urls.append(resourceURL.appendingPathComponent(".env"))
        }

        #if DEBUG
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".env"))
        #endif

        return urls
    }

    private func parse(contents: String) -> [String: String] {
        contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                    return
                }

                let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)

                guard parts.count == 2 else {
                    return
                }

                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = stripWrappingQuotes(
                    from: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                )

                result[key] = value
            }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func stripWrappingQuotes(from value: String) -> String {
        guard value.count >= 2 else { return value }

        let firstCharacter = value.first
        let lastCharacter = value.last

        if (firstCharacter == "\"" && lastCharacter == "\"") || (firstCharacter == "'" && lastCharacter == "'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case invalidResponse
    case missingModelText
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Missing GEMINI_API_KEY in the local .env file."
        case .imageEncodingFailed:
            "Could not convert the image to JPEG data."
        case .invalidResponse:
            "Gemini returned a response that could not be interpreted."
        case .missingModelText:
            "Gemini returned no text content."
        case let .requestFailed(statusCode, body):
            "Gemini request failed with status \(statusCode): \(body)"
        }
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let inlineData: GeminiInlineData?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}
