import Foundation

// MARK: - 网络兼容（异步 URLSession 方法封装，纯 Foundation，mac/iOS 通用）

enum Net {
    static func data(_ req: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { c in
            let t = URLSession.shared.dataTask(with: req) { d, r, e in
                if let e = e { c.resume(throwing: e) }
                else { c.resume(returning: (d ?? Data(), r!)) }
            }
            t.resume()
        }
    }
    static func upload(_ body: Data, _ req: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { c in
            let t = URLSession.shared.uploadTask(with: req, from: body) { d, r, e in
                if let e = e { c.resume(throwing: e) }
                else { c.resume(returning: (d ?? Data(), r!)) }
            }
            t.resume()
        }
    }
    static func download(_ req: URLRequest) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { c in
            let t = URLSession.shared.downloadTask(with: req) { url, r, e in
                if let e = e { c.resume(throwing: e) }
                else if let url = url { c.resume(returning: (url, r!)) }
                else { c.resume(throwing: URLError(.cannotOpenFile)) }
            }
            t.resume()
        }
    }
}
