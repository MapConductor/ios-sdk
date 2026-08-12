import Foundation
import zlib

enum KMZArchiveError: LocalizedError {
    case invalidArchive
    case entryNotFound(String)
    case unsupportedCompression(Int)
    case decompressionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "Invalid KMZ (ZIP) archive"
        case .entryNotFound(let what): return "KMZ archive contains no \(what) entry"
        case .unsupportedCompression(let method): return "Unsupported ZIP compression method: \(method)"
        case .decompressionFailed(let status): return "ZIP decompression failed with zlib status \(status)"
        }
    }
}

/// KMZ（ZIP でまとめた KML）を読むための小さな ZIP リーダ。
///
/// react-sdk の `GeoJSONZipArchive.swift` と同じセントラルディレクトリ走査で、
/// Stored（無圧縮）と Deflate の 2 方式を zlib で展開する。入力はファイルではなく
/// ``KMLParser`` が受け取った `Data` そのもの。
enum KMZArchive {
    /// ZIP local-file-header signature: PK\x03\x04.
    static func isZipArchive(_ data: Data) -> Bool {
        data.count >= 4 &&
            data[data.startIndex] == 0x50 &&
            data[data.startIndex + 1] == 0x4B &&
            data[data.startIndex + 2] == 0x03 &&
            data[data.startIndex + 3] == 0x04
    }

    /// Returns the data of the first entry whose name ends in `.pathExtension`
    /// (case-insensitive), skipping directories and `__MACOSX/` metadata entries.
    static func firstEntryData(archive: Data, pathExtension: String) throws -> Data {
        try entryData(archive: archive, what: ".\(pathExtension)") { path in
            !path.hasPrefix("__MACOSX/")
                && !path.hasSuffix("/")
                && path.lowercased().hasSuffix(".\(pathExtension.lowercased())")
        }
    }

    private static func entryData(
        archive data: Data,
        what: String,
        matching predicate: (String) -> Bool
    ) throws -> Data {
        // Data のスライス（startIndex != 0）でも絶対オフセットで読めるよう再基準化する。
        let archive = data.startIndex == 0 ? data : Data(data)
        var offset = 0
        var foundCentralDirectory = false
        while offset + 46 <= archive.count {
            guard uint32(in: archive, at: offset) == 0x0201_4b50 else {
                offset += 1
                continue
            }
            foundCentralDirectory = true

            let method = Int(uint16(in: archive, at: offset + 10))
            let compressedSize = Int(uint32(in: archive, at: offset + 20))
            let uncompressedSize = Int(uint32(in: archive, at: offset + 24))
            let nameLength = Int(uint16(in: archive, at: offset + 28))
            let extraLength = Int(uint16(in: archive, at: offset + 30))
            let commentLength = Int(uint16(in: archive, at: offset + 32))
            let localHeaderOffset = Int(uint32(in: archive, at: offset + 42))
            let nextOffset = offset + 46 + nameLength + extraLength + commentLength
            guard nextOffset <= archive.count else {
                throw KMZArchiveError.invalidArchive
            }

            let nameStart = offset + 46
            let nameData = archive.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            if predicate(name) {
                guard localHeaderOffset + 30 <= archive.count,
                      uint32(in: archive, at: localHeaderOffset) == 0x0403_4b50 else {
                    throw KMZArchiveError.invalidArchive
                }
                let localNameLength = Int(uint16(in: archive, at: localHeaderOffset + 26))
                let localExtraLength = Int(uint16(in: archive, at: localHeaderOffset + 28))
                let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
                let dataEnd = dataStart + compressedSize
                guard dataStart >= 0, dataEnd <= archive.count else {
                    throw KMZArchiveError.invalidArchive
                }
                let compressed = archive.subdata(in: dataStart..<dataEnd)
                switch method {
                case 0: return compressed
                case 8: return try inflateRawDeflate(compressed, expectedSize: uncompressedSize)
                default: throw KMZArchiveError.unsupportedCompression(method)
                }
            }
            offset = nextOffset
        }
        guard foundCentralDirectory else {
            throw KMZArchiveError.invalidArchive
        }
        throw KMZArchiveError.entryNotFound(what)
    }

    private static func inflateRawDeflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let result: (status: Int32, written: Int) = compressed.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                guard let input = inputBuffer.bindMemory(to: Bytef.self).baseAddress,
                      let destination = outputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return (Z_BUF_ERROR, 0)
                }
                var stream = z_stream()
                stream.next_in = UnsafeMutablePointer(mutating: input)
                stream.avail_in = uInt(inputBuffer.count)
                stream.next_out = destination
                stream.avail_out = uInt(outputBuffer.count)
                let initStatus = inflateInit2_(
                    &stream,
                    -MAX_WBITS,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
                guard initStatus == Z_OK else { return (initStatus, 0) }
                defer { inflateEnd(&stream) }
                let status = inflate(&stream, Z_FINISH)
                return (status, Int(stream.total_out))
            }
        }
        guard result.status == Z_STREAM_END else {
            throw KMZArchiveError.decompressionFailed(result.status)
        }
        output.count = result.written
        return output
    }

    private static func uint16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
