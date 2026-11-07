import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The process's memory by kind, from walking its virtual memory regions and adding
/// up the pages each one has written (dirty or swapped), grouped by the tag the system
/// gives the region: Core Animation layers, IOSurfaces, malloc, stacks and so on. It
/// says where the part of the footprint that isn't heap or graphics lives.
///
/// Walking the regions takes a few milliseconds, so it runs on show, hide and memory
/// warnings and every few seconds while the stats overlay is on, not on every reading.
///
///     MemoryRegions.current().map(MemoryRegions.line)   // "CA 31.2 · malloc 26.0 · IOSurface 8.1 · anon 4.0"
public enum MemoryRegions {
    /// Written MB by region tag. Nil off Darwin.
    public static func current() -> [Int: Double]? {
        #if canImport(Darwin)
        var byTag: [Int: Double] = [:]
        var address: vm_address_t = 0
        let page = Double(vm_page_size)
        let wordCount = MemoryLayout<vm_region_extended_info_data_t>.size / MemoryLayout<natural_t>.size
        for _ in 0..<100_000 {
            var size: vm_size_t = 0
            var info = vm_region_extended_info_data_t()
            var count = mach_msg_type_number_t(wordCount)
            var object: mach_port_t = 0
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: wordCount) {
                    vm_region_64(mach_task_self_, &address, &size, VM_REGION_EXTENDED_INFO, $0, &count, &object)
                }
            }
            guard result == KERN_SUCCESS else { break }
            let written = Double(info.pages_dirtied) + Double(info.pages_swapped_out)
            if written > 0 { byTag[Int(info.user_tag), default: 0] += written * page / 1_048_576 }
            address += size
        }
        return byTag
        #else
        return nil
        #endif
    }

    /// The biggest kinds, largest first, malloc's tags added together:
    /// "CA 31.2 · malloc 26.0 · IOSurface 8.1". Kinds under 0.5 MB are left out.
    public static func line(_ byTag: [Int: Double], top: Int = 6) -> String {
        var byName: [String: Double] = [:]
        for (tag, mb) in byTag { byName[name(tag), default: 0] += mb }
        return byName.filter { $0.value >= 0.5 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(top)
            .map { "\($0.key) \(MemoryReading.mb($0.value))" }
            .joined(separator: " · ")
    }

    /// A short name for a region tag (`VM_MEMORY_*` in mach/vm_statistics.h).
    static func name(_ tag: Int) -> String {
        switch tag {
        case 0: "anon"
        case 1...4, 6...9, 11, 12: "malloc"
        case 20: "mach"
        case 21: "iokit"
        case 30: "stack"
        case 33, 60, 61: "dyld"
        case 41: "foundation"
        case 42, 52, 54...58: "CG"
        case 51: "CA"
        case 68: "CoreImage"
        case 70: "ImageIO"
        case 73: "once"
        case 74: "dispatch"
        case 76, 77, 103: "CoreUI"
        case 82, 83: "swift"
        case 88: "IOSurface"
        case 100: "IOAccel"
        case 104: "ColorSync"
        default: "tag \(tag)"
        }
    }
}
