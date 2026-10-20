import Foundation

public enum InsertionVerification {
    public static func expectedValue(before: String, location: Int, length: Int, text: String) -> String? {
        let source = before as NSString
        guard location >= 0, length >= 0, location <= source.length,
              length <= source.length - location else { return nil }
        return source.replacingCharacters(in: NSRange(location: location, length: length), with: text)
    }
    public static func confirms(expected: String?, actual: String?) -> Bool {
        guard let expected, let actual else { return false }
        return expected == actual
    }
}
