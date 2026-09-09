import Foundation

struct APIError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

enum JSONValue {
    static func string(_ obj: Any?, _ keyPath: [String]) -> String? {
        var cur = obj
        for k in keyPath {
            guard let d = cur as? [String: Any], let v = d[k] else { return nil }
            cur = v
        }
        if let s = cur as? String { return s }
        if let n = cur as? NSNumber { return n.stringValue }
        return nil
    }
    static func dict(_ obj: Any?, _ key: String) -> [String: Any]? {
        (obj as? [String: Any])?[key] as? [String: Any]
    }
    static func int(_ obj: Any?, _ keyPath: [String]) -> Int? {
        var cur = obj
        for k in keyPath {
            guard let d = cur as? [String: Any], let v = d[k] else { return nil }
            cur = v
        }
        if let n = cur as? Int { return n }
        if let n = cur as? NSNumber { return n.intValue }
        if let s = cur as? String { return Int(s) }
        return nil
    }
}
