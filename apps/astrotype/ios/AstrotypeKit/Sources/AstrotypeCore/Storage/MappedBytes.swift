import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read-only bytes that tables are read from in place: a file mapped into memory, or a
/// copy of some `Data`. A mapped file is read from storage only as its pages are
/// touched, and those pages are clean, so iOS doesn't count them against the keyboard's
/// memory limit and can drop them and read them again when memory is tight. That is how
/// the dictionaries stay out of the keyboard's footprint (`Lexicon`, `NgramModel`).
///
///     let bytes = try MappedBytes(mapping: url)
///     let starts: UnsafeBufferPointer<Int32> = bytes.buffer(at: 32, count: nodes)
final class MappedBytes: @unchecked Sendable {
    let base: UnsafeRawPointer
    let count: Int
    /// Whether `base` is a file mapping (unmapped when freed) rather than our own copy.
    let isMapped: Bool

    /// A copy of `data` in memory, laid out the same as a mapped file.
    init(copying data: Data) {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: max(data.count, 1), alignment: 16)
        data.withUnsafeBytes { raw in
            if let source = raw.baseAddress { pointer.copyMemory(from: source, byteCount: raw.count) }
        }
        base = UnsafeRawPointer(pointer)
        count = data.count
        isMapped = false
    }

    /// The file at `url`, mapped read-only.
    init(mapping url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size > 0 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let size = Int(info.st_size)
        let mapped: UnsafeMutableRawPointer? = mmap(nil, size, PROT_READ, MAP_PRIVATE, descriptor, 0)
        guard let mapped, mapped != UnsafeMutableRawPointer(bitPattern: -1) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        base = UnsafeRawPointer(mapped)
        count = size
        isMapped = true
    }

    deinit {
        if isMapped {
            munmap(UnsafeMutableRawPointer(mutating: base), count)
        } else {
            UnsafeMutableRawPointer(mutating: base).deallocate()
        }
    }

    /// `count` values of `T` starting `offset` bytes in. The caller has checked they fit.
    func buffer<T>(at offset: Int, count: Int, as type: T.Type = T.self) -> UnsafeBufferPointer<T> {
        UnsafeBufferPointer(start: base.advanced(by: offset).bindMemory(to: T.self, capacity: max(count, 1)), count: count)
    }

    /// Whether both hold the same bytes.
    func sameBytes(as other: MappedBytes) -> Bool {
        count == other.count && memcmp(base, other.base, count) == 0
    }
}

/// Reads a table file's sections in the order they were written, each starting on a
/// 4-byte boundary, and checks they fit.
struct SectionReader {
    let bytes: MappedBytes
    private(set) var offset: Int

    init(_ bytes: MappedBytes, after header: Int) {
        self.bytes = bytes
        offset = header
    }

    mutating func next<T>(_ count: Int, as type: T.Type = T.self) throws -> UnsafeBufferPointer<T> {
        offset = (offset + 3) & ~3
        let size = count * MemoryLayout<T>.stride
        guard count >= 0, offset + size <= bytes.count else { throw TableFileError.corrupt }
        defer { offset += size }
        return bytes.buffer(at: offset, count: count)
    }
}

/// Writes a table file: little-endian values, each section starting on a 4-byte boundary.
struct SectionWriter {
    private(set) var data = Data()

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: Float) { append(value.bitPattern) }

    mutating func pad() {
        while data.count % 4 != 0 { data.append(0) }
    }

    mutating func section<T: FixedWidthInteger>(_ values: [T]) {
        pad()
        // Native order, which is little-endian on every phone and Mac we build for.
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }

    mutating func section(_ values: [Float]) {
        section(values.map(\.bitPattern))
    }
}

enum TableFileError: Error, Equatable {
    case corrupt
}
