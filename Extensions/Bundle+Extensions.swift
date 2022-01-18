
import Foundation

extension Bundle {
    // https://newbedev.com/get-app-name-in-swift
    var displayName: String? {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
