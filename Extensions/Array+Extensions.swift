
import Foundation

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var set = Set<Element>()
        for value in self {
            if !set.contains(value) {
                set.insert(value)
            }
        }
        return Array(set)
    }
}
