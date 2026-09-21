import Foundation

/// 用户可见文案。跟随系统语言，英文为开发语言，中文在 `zh-Hans.lproj`。
enum L10n {
    /// 按 key 取当前语言文案。
    /// - Parameter key: `Localizable.strings` 中的键，缺省回退为英文表。
    static func s(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// 带参数的文案。
    /// - Parameters:
    ///   - key: 含 `%@` / `%d` / `%.1f` 的格式串键。
    ///   - args: 按格式串顺序填入。
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }
}
