//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class Smartling {
    let projectIdentifier: String
    let userIdentifier: String
    let userSecret: String

    init(projectIdentifier: String, userIdentifier: String, userSecret: String) {
        self.projectIdentifier = projectIdentifier
        self.userIdentifier = userIdentifier
        self.userSecret = userSecret
    }

    fileprivate struct Token {
        var accessToken: String
        var expirationDate: Date
    }

    private var latestTokenTask: Task<Token, Error>?

    @MainActor
    private func fetchToken() async throws -> Token {
        assert(Thread.isMainThread)
        if let latestToken = try await latestTokenTask?.value, latestToken.expirationDate.timeIntervalSinceNow > 5 {
            return latestToken
        }
        let task = Task {
            let rawToken = try await fetchNewToken()
            let newToken = Token(
                accessToken: rawToken.accessToken,
                expirationDate: Date(timeIntervalSinceNow: TimeInterval(rawToken.expiresIn))
            )
            print("Got new token that expires at \(newToken.expirationDate)")
            return newToken
        }
        latestTokenTask = task
        return try await task.value
    }

    struct FetchedToken: Decodable {
        var accessToken: String
        var expiresIn: Int
    }

    private func fetchNewToken() async throws -> FetchedToken {
        struct AuthenticationRequest: Encodable {
            var userIdentifier: String
            var userSecret: String
        }

        let request = AuthenticationRequest(userIdentifier: userIdentifier, userSecret: userSecret)
        return try await postRequest(urlPath: "/auth-api/v2/authenticate", request: request)
    }

    func uploadSourceFile(at fileURL: URL) async throws {
        let urlPath = "/files-api/v2/projects/\(projectIdentifier)/file"
        var urlRequest = buildRequest(url: buildURL(path: urlPath), token: try await fetchToken())
        urlRequest.httpMethod = "POST"
        try urlRequest.addFile(at: fileURL)
        _ = try await URLSession.shared.data(for: urlRequest, expecting: 200)
    }

    func downloadTranslatedFile(for filename: String, in localeIdentifier: String) async throws -> URL {
        let urlPath = "/files-api/v2/projects/\(projectIdentifier)/locales/\(localeIdentifier)/file"
        let url = buildURL(path: urlPath, queryItems: [
            "fileUri": filename,
            "retrievalType": "published",
            "includeOriginalStrings": "true"
        ])
        var urlRequest = buildRequest(url: url, token: try await fetchToken())
        urlRequest.httpMethod = "GET"
        return try await URLSession.shared.download(for: urlRequest, expecting: 200)
    }
}

private extension Smartling {
    func buildURL(path: String, queryItems: [String: String]? = nil) -> URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "api.smartling.com"
        urlComponents.path = path
        urlComponents.queryItems = queryItems?.map { URLQueryItem(name: $0.key, value: $0.value) }
        return urlComponents.url!
    }

    func buildRequest(url: URL, token: Token? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = token {
            request.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // Wraps a JSON response from Smartling.
    struct Response<T: Decodable>: Decodable {
        var response: WrappedResponse
        struct WrappedResponse: Decodable {
            var data: T
        }
    }

    func postRequest<Req: Encodable, Resp: Decodable>(urlPath: String, request: Req) async throws -> Resp {
        var urlRequest = buildRequest(url: buildURL(path: urlPath))
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let responseData = try await URLSession.shared.data(for: urlRequest, expecting: 200)
        let wrappedResponse = try JSONDecoder().decode(Response<Resp>.self, from: responseData)
        return wrappedResponse.response.data
    }
}

extension URLRequest {
    mutating func addFile(at fileURL: URL) throws {
        let boundary = UUID().uuidString
        setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let filename = fileURL.lastPathComponent
        httpBody = Self.multipartFormData(boundary: boundary, items: [
            ("file", .file(name: filename, value: try Data(contentsOf: fileURL))),
            ("fileUri", .text(value: filename)),
            ("fileType", .text(value: Self.fileType(for: fileURL)))
        ])
    }

    private enum MultipartFormDataItem {
        case text(value: String)
        case file(name: String, value: Data)
    }

    private static func multipartFormData(boundary: String, items: [(String, MultipartFormDataItem)]) -> Data {
        var result = Data()
        func addLine(_ dataValue: Data) {
            result.append(dataValue)
            result.append("\r\n".data(using: .utf8)!)
        }
        func addLine(_ stringValue: String) {
            addLine(stringValue.data(using: .utf8)!)
        }
        for (fieldName, item) in items {
            addLine("--\(boundary)")
            switch item {
            case let .text(value):
                addLine("Content-Disposition: form-data; name=\"\(fieldName)\"")
                addLine("")
                addLine(value)
            case let .file(name, value):
                addLine("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(name)\"")
                addLine("Content-Type: application/octet-stream")
                addLine("")
                addLine(value)
            }
        }
        addLine("--\(boundary)--")
        return result
    }

    private static func fileType(for url: URL) -> String {
        let pathExtension = url.pathExtension
        switch pathExtension {
        case "txt":
            return "plain_text"
        case "strings":
            return "ios"
        case "stringsdict":
            return "stringsdict"
        default:
            fatalError("Can't upload file with .\(pathExtension) extension")
        }
    }
}

private extension URLSession {
    enum HTTPError: Error {
        case statusCode(Int?)
    }

    func data(for urlRequest: URLRequest, expecting expectedStatusCode: Int) async throws -> Data {
        let (data, urlResponse) = try await data(for: urlRequest)
        try handleResponse(urlResponse: urlResponse, expecting: expectedStatusCode)
        return data
    }

    func download(for urlRequest: URLRequest, expecting expectedStatusCode: Int) async throws -> URL {
        let (data, urlResponse) = try await download(for: urlRequest)
        try handleResponse(urlResponse: urlResponse, expecting: expectedStatusCode)
        return data
    }

    private func handleResponse(urlResponse: URLResponse, expecting expectedStatusCode: Int) throws {
        let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode
        guard statusCode == expectedStatusCode else {
            throw HTTPError.statusCode(statusCode)
        }
    }
}
