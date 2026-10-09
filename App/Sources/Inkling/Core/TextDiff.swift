import Foundation

/// The smallest edit between two strings, in UTF-16 units.
struct TextEdit {
    /// Where the change starts (same in both strings).
    let location: Int
    /// End of the replaced region in the *old* string.
    let oldEnd: Int
    /// End of the inserted region in the *new* string.
    let newEnd: Int

    var delta: Int { newEnd - oldEnd }

    init(from old: String, to new: String) {
        let o = Array(old.utf16)
        let n = Array(new.utf16)
        var prefix = 0
        let maxPrefix = min(o.count, n.count)
        while prefix < maxPrefix, o[prefix] == n[prefix] { prefix += 1 }
        var suffix = 0
        let maxSuffix = min(o.count, n.count) - prefix
        while suffix < maxSuffix, o[o.count - 1 - suffix] == n[n.count - 1 - suffix] { suffix += 1 }
        location = prefix
        oldEnd = o.count - suffix
        newEnd = n.count - suffix
    }
}

extension Array where Element == Lint {
    /// Move lints so they keep pointing at the same words after an edit.
    /// Lints touching the edited region are dropped (they'll be re-checked).
    func remapped(from old: String, to new: String) -> [Lint] {
        if old == new { return self }
        let edit = TextEdit(from: old, to: new)
        let newUnits = [UInt16](new.utf16)

        func isWordUnit(_ u: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(UInt32(u)) else { return true }
            return CharacterSet.alphanumerics.contains(scalar) || u == 39 || u == 0x2019
        }

        return compactMap { lint in
            if lint.end < edit.location { return lint }
            if lint.end == edit.location {
                // Typing (or deleting) right after a word glues new letters onto it — stale.
                if edit.location < newUnits.count, isWordUnit(newUnits[edit.location]) { return nil }
                return lint
            }
            if lint.start > edit.oldEnd { return lint.shifted(by: edit.delta) }
            if lint.start == edit.oldEnd {
                let before = edit.newEnd - 1
                if before >= 0, before < newUnits.count, isWordUnit(newUnits[before]) { return nil }
                return lint.shifted(by: edit.delta)
            }
            return nil
        }
    }
}
