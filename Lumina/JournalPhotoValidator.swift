import Foundation

/// Completeness checks for declared TIFF ranges, before ImageIO's bounded decode.
/// A readable preview can survive missing ICC/profile metadata. Do not discard
/// that metadata, recompress the image, or assume TIFF has a mandatory trailer.
nonisolated enum JournalPhotoValidator {
    static func validateTIFFContainer(_ data: Data, budget: JournalTransferBudget?) throws {
        let validationBudget = budget ?? JournalTransferBudget(seconds: JournalTransferLimits.standard.deadlineSeconds)
        try validationBudget.check()
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            func require(_ condition: Bool) throws {
                guard condition else { throw JournalTransferError.invalid }
            }
            try require(bytes.count >= 8)
            let little = bytes[0] == 0x49 && bytes[1] == 0x49
            try require(little || (bytes[0] == 0x4d && bytes[1] == 0x4d))
            let fileBytes = UInt64(bytes.count)
            func contains(_ start: UInt64, _ count: UInt64) -> Bool {
                start <= fileBytes && count <= fileBytes - start
            }
            // Callers establish the complete range before any byte is read.
            func unsigned(_ start: Int, _ width: Int) -> UInt64 {
                var value: UInt64 = 0
                for index in 0..<width {
                    let position = little ? start + width - 1 - index : start + index
                    value = (value << 8) | UInt64(bytes[position])
                }
                return value
            }
            let version = unsigned(2, 2)
            try require(version == 42 || version == 43)
            let big = version == 43
            if big {
                try require(bytes.count >= 16 && unsigned(4, 2) == 8 && unsigned(6, 2) == 0)
            }
            let countWidth = big ? 8 : 2, offsetWidth = big ? 8 : 4
            let entryWidth = big ? 20 : 12, valuePosition = big ? 12 : 8
            let firstDirectory = unsigned(big ? 8 : 4, offsetWidth)
            try require(firstDirectory != 0)
            typealias Cursor = (offset: UInt64, entries: Int, count: Int,
                                entryIndex: Int, valueIndex: Int, followedNext: Bool)
            func directory(_ next: UInt64) throws -> Cursor {
                try validationBudget.check()
                try require(contains(next, UInt64(countWidth + offsetWidth)))
                let start = Int(next), count = unsigned(start, countWidth)
                let available = bytes.count - start - countWidth - offsetWidth
                try require(count > 0 && count <= UInt64(available / entryWidth))
                let entries = start + countWidth
                var ranges: [UInt64: (offset: Int, count: Int, width: Int)] = [:]
                for index in 0..<Int(count) {
                    if (index & 63) == 0 { try validationBudget.check() }
                    let entry = entries + index * entryWidth
                    let tag = unsigned(entry, 2), type = unsigned(entry + 2, 2)
                    let values = unsigned(entry + 4, big ? 8 : 4)
                    let width: Int
                    switch type {
                    case 1, 2, 6, 7: width = 1
                    case 3, 8: width = 2
                    case 4, 9, 11, 13: width = 4
                    case 5, 10, 12, 16, 17, 18: width = 8
                    default:
                        // TIFF requires readers to ignore future field types;
                        // their unknown byte width cannot be inferred safely.
                        continue
                    }
                    try require(values <= fileBytes / UInt64(width))
                    let size = values * UInt64(width)
                    let location = size <= UInt64(offsetWidth) ? UInt64(entry + valuePosition)
                        : unsigned(entry + valuePosition, offsetWidth)
                    try require(contains(location, size))
                    // Bound explicitly declared strips, tiles and legacy JPEG
                    // streams too. No assumptions about their order or overlap.
                    if [UInt64(273), 279, 324, 325, 513, 514].contains(tag),
                       [UInt64(1), 3, 4, 16].contains(type) {
                        try require(ranges[tag] == nil)
                        ranges[tag] = (Int(location), Int(values), width)
                    }
                }
                for (offsetTag, countTag) in [(UInt64(273), UInt64(279)), (324, 325), (513, 514)] {
                    // ImageIO handles format requirements and codecs. Here we
                    // check ranges when both standardized declarations exist.
                    guard let offsets = ranges[offsetTag], let sizes = ranges[countTag] else { continue }
                    try require(offsets.count == sizes.count)
                    for index in 0..<offsets.count {
                        if (index & 63) == 0 { try validationBudget.check() }
                        let location = unsigned(offsets.offset + index * offsets.width, offsets.width)
                        let size = unsigned(sizes.offset + index * sizes.width, sizes.width)
                        try require(contains(location, size))
                    }
                }
                return (next, entries, Int(count), 0, 0, false)
            }
            func child(_ cursor: inout Cursor) throws -> UInt64? {
                // Stream pointer arrays. Several fields may alias the same
                // large array; never concatenate those references in memory.
                while cursor.entryIndex < cursor.count {
                    try validationBudget.check()
                    let entry = cursor.entries + cursor.entryIndex * entryWidth
                    let tag = unsigned(entry, 2), type = unsigned(entry + 2, 2)
                    let isDirectoryType = type == 13 || type == 18
                    let isDirectoryTag = [UInt64(330), 34665, 34853, 40965].contains(tag)
                    let width: Int
                    switch type {
                    case 1: width = 1
                    case 3: width = 2
                    case 4, 13: width = 4
                    case 16, 18: width = 8
                    default: width = 0
                    }
                    if width > 0 && (isDirectoryType || isDirectoryTag) {
                        // directory() already bounded this entire typed array.
                        let count = Int(unsigned(entry + 4, big ? 8 : 4))
                        let size = count * width
                        let location = size <= offsetWidth ? entry + valuePosition
                            : Int(unsigned(entry + valuePosition, offsetWidth))
                        while cursor.valueIndex < count {
                            if (cursor.valueIndex & 63) == 0 { try validationBudget.check() }
                            let pointer = unsigned(location + cursor.valueIndex * width, width)
                            cursor.valueIndex += 1
                            if pointer != 0 { return pointer }
                        }
                    }
                    cursor.entryIndex += 1; cursor.valueIndex = 0
                }
                if !cursor.followedNext {
                    cursor.followedNext = true
                    let pointer = unsigned(cursor.entries + cursor.count * entryWidth, offsetWidth)
                    if pointer != 0 { return pointer }
                }
                return nil
            }
            var stack: [Cursor] = [try directory(firstDirectory)]
            var active: Set<UInt64> = [firstDirectory], complete: Set<UInt64> = []
            while var cursor = stack.popLast() {
                try validationBudget.check()
                guard let next = try child(&cursor) else {
                    active.remove(cursor.offset); complete.insert(cursor.offset)
                    continue
                }
                stack.append(cursor)
                // Repeated SubIFD entries or a shared next-IFD/child target are
                // valid. Only a reference into the current DFS path is a cycle.
                if complete.contains(next) { continue }
                try require(!active.contains(next))
                let descendant = try directory(next)
                active.insert(next); stack.append(descendant)
            }
        }
    }
}
