import UIKit

enum DeviceInfo {
    /// Hardware model, e.g. "iPhone17,1".
    static let model: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    @MainActor static var system: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }()

    /// A random ID for this install, so one person's samples can be grouped
    /// without knowing who they are.
    static let writerID: String = {
        let key = "writerID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}
