import Cocoa

/// Generic Webhook uploader that sends images/files via HTTP POST to any endpoint.
/// Supports multipart/form-data upload with configurable headers and response URL extraction.
final class WebhookUploader {

    static let shared = WebhookUploader()

    struct Config {
        let url: String               // POST endpoint URL
        let fieldName: String         // multipart field name (default: "file")
        let headers: [String: String] // custom headers (e.g. Authorization)
        let responseURLPath: String   // JSON key path to extract URL from response (e.g. "data.url")

        var isValid: Bool { !url.isEmpty }
    }

    var config: Config {
        let ud = UserDefaults.standard
        let headersString = ud.string(forKey: "webhookHeaders") ?? ""
        var headers: [String: String] = [:]
        for line in headersString.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return Config(
            url: ud.string(forKey: "webhookURL") ?? "",
            fieldName: ud.string(forKey: "webhookFieldName") ?? "file",
            headers: headers,
            responseURLPath: ud.string(forKey: "webhookResponseURLPath") ?? "url"
        )
    }

    var isConfigured: Bool { config.isValid }

    /// Progress callback (0.0–1.0), called on main thread.
    var onProgress: ((Double) -> Void)?

    // MARK: - Upload Image

    func uploadImage(_ image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion(.failure(Self.error("Failed to encode image")))
            return
        }
        upload(data: pngData, filename: "screenshot.png", contentType: "image/png", completion: completion)
    }

    /// Upload arbitrary file data.
    func upload(data: Data, filename: String, contentType: String,
                completion: @escaping (Result<String, Error>) -> Void) {
        let cfg = config
        guard cfg.isValid, let url = URL(string: cfg.url) else {
            completion(.failure(Self.error("Webhook URL is not configured")))
            return
        }

        let boundary = "ScreenShot-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Apply custom headers
        for (key, value) in cfg.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(cfg.fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot_webhook_\(UUID().uuidString).tmp")
        try? body.write(to: tmpFile)

        let session = URLSession(configuration: .default, delegate: ProgressDelegate(onProgress: { [weak self] p in
            DispatchQueue.main.async { self?.onProgress?(p) }
        }), delegateQueue: nil)

        let task = session.uploadTask(with: request, fromFile: tmpFile) { [weak self] responseData, response, error in
            try? FileManager.default.removeItem(at: tmpFile)

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async { completion(.failure(Self.error("HTTP \(code)"))) }
                return
            }

            // Try to extract URL from response
            var resultURL = cfg.url
            if let data = responseData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resultURL = self?.extractValue(from: json, keyPath: cfg.responseURLPath) as? String ?? cfg.url
            }

            DispatchQueue.main.async { completion(.success(resultURL)) }
        }
        task.resume()
    }

    // MARK: - Helpers

    /// Extract a nested value using dot-separated key path (e.g. "data.url")
    private func extractValue(from dict: [String: Any], keyPath: String) -> Any? {
        let keys = keyPath.split(separator: ".").map(String.init)
        var current: Any = dict
        for key in keys {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current
    }

    private static func error(_ msg: String) -> NSError {
        NSError(domain: "WebhookUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    // MARK: - Progress Delegate

    private class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let onProgress: (Double) -> Void
        init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                        totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }
}
