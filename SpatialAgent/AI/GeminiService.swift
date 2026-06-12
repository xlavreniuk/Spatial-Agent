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

    private var endpointURL: URL {
        endpointBaseURL
            .appendingPathComponent(model + ":generateContent")
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
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Missing GEMINI_API_KEY in the local .env file."
        case .imageEncodingFailed:
            "Could not convert the image to JPEG data."
        case .invalidResponse:
            "Gemini returned a response that could not be interpreted."
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
