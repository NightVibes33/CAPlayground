import Foundation

enum ZIPArchiveError: Error { case invalidArchive, stringEncoding }

struct ZIPEntry {
    var path: String
    var data: Data
}

enum ZIPArchive {
    static func create(entries: [ZIPEntry]) -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let offset = UInt32(output.count)
            let checksum = crc32(entry.data)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(checksum); output.appendLE(UInt32(entry.data.count)); output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0)); output.append(name); output.append(entry.data)

            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(0x0314)); central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(checksum); central.appendLE(UInt32(entry.data.count)); central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt32(0)); central.appendLE(offset); central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count)); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        return output
    }

    /// Rebuilds a ZIP while preserving existing compressed local records byte-for-byte.
    /// Replacement entries are stored without compression and take the original paths.
    static func replacing(in archive: Data, with replacements: [ZIPEntry]) throws -> Data {
        guard let eocd = archive.lastRange(of: Data([0x50, 0x4b, 0x05, 0x06])), eocd.lowerBound + 22 <= archive.count else {
            throw ZIPArchiveError.invalidArchive
        }
        let centralOffset = Int(archive.u32(at: eocd.lowerBound + 16))
        let count = Int(archive.u16(at: eocd.lowerBound + 10))
        var cursor = centralOffset
        var originals: [(path: String, localOffset: Int, central: Data)] = []
        for _ in 0..<count {
            guard archive.u32(at: cursor) == 0x02014b50 else { throw ZIPArchiveError.invalidArchive }
            let nameLength = Int(archive.u16(at: cursor + 28))
            let extraLength = Int(archive.u16(at: cursor + 30))
            let commentLength = Int(archive.u16(at: cursor + 32))
            let total = 46 + nameLength + extraLength + commentLength
            guard cursor + total <= archive.count,
                  let path = String(data: archive[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) else {
                throw ZIPArchiveError.stringEncoding
            }
            originals.append((path, Int(archive.u32(at: cursor + 42)), archive[cursor..<(cursor + total)]))
            cursor += total
        }
        let replacementPaths = Set(replacements.map(\.path))
        let kept = originals.filter { !replacementPaths.contains($0.path) }.sorted { $0.localOffset < $1.localOffset }
        var output = Data()
        var centralRecords: [Data] = []
        for (index, item) in kept.enumerated() {
            let end = index + 1 < kept.count ? kept[index + 1].localOffset : centralOffset
            guard item.localOffset < end, end <= archive.count else { throw ZIPArchiveError.invalidArchive }
            let newOffset = UInt32(output.count)
            output.append(archive[item.localOffset..<end])
            var record = item.central
            record.replaceLE(at: 42, value: newOffset)
            centralRecords.append(record)
        }
        for replacement in replacements {
            let name = Data(replacement.path.utf8), offset = UInt32(output.count), checksum = crc32(replacement.data)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(checksum); output.appendLE(UInt32(replacement.data.count)); output.appendLE(UInt32(replacement.data.count)); output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0)); output.append(name); output.append(replacement.data)
            var record = Data(); record.appendLE(UInt32(0x02014b50)); record.appendLE(UInt16(0x0314)); record.appendLE(UInt16(20)); record.appendLE(UInt16(0x0800)); record.appendLE(UInt16(0)); record.appendLE(UInt16(0)); record.appendLE(UInt16(0)); record.appendLE(checksum); record.appendLE(UInt32(replacement.data.count)); record.appendLE(UInt32(replacement.data.count)); record.appendLE(UInt16(name.count)); record.appendLE(UInt16(0)); record.appendLE(UInt16(0)); record.appendLE(UInt16(0)); record.appendLE(UInt16(0)); record.appendLE(UInt32(0)); record.appendLE(offset); record.append(name); centralRecords.append(record)
        }
        let offset = UInt32(output.count)
        let central = centralRecords.reduce(into: Data()) { $0.append($1) }
        output.append(central); output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(centralRecords.count)); output.appendLE(UInt16(centralRecords.count)); output.appendLE(UInt32(central.count)); output.appendLE(offset); output.appendLE(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) } }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } }
    func u16(at offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(at offset: Int) -> UInt32 { UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24 }
    mutating func replaceLE(at offset: Int, value: UInt32) { self[offset] = UInt8(value & 0xff); self[offset + 1] = UInt8((value >> 8) & 0xff); self[offset + 2] = UInt8((value >> 16) & 0xff); self[offset + 3] = UInt8((value >> 24) & 0xff) }
    func lastRange(of needle: Data) -> Range<Int>? {
        guard count >= needle.count else { return nil }
        for index in stride(from: count - needle.count, through: 0, by: -1) where self[index..<(index + needle.count)].elementsEqual(needle) { return index..<(index + needle.count) }
        return nil
    }
}
