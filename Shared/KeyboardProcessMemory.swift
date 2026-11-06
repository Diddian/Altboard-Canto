import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if os(iOS)
import os
#endif

/// Low-frequency, process-local memory measurements for development diagnostics.
/// Never contains typed characters, host content, paths, or device identifiers.
enum KeyboardProcessMemory {
  struct Snapshot: Codable, Sendable {
    let footprintMiB: Int?
    let residentMiB: Int?
    let availableMiB: Int?
    let estimatedBudgetMiB: Int?
  }

  // Stable across keyboard controllers in one extension process, but changes
  // after iOS launches another extension process.
  static let processLaunchID = String(UUID().uuidString.prefix(8))

  static func snapshot() -> Snapshot? {
    #if os(iOS) && !APPSTORE
    // Apple's advisory headroom is much cheaper than Mach task_info.
    let headroom = UInt64(os_proc_available_memory())
    let available = headroom > 0 ? mebibytes(headroom) : nil

    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { values in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), values, &count)
      }
    }
    let required = MemoryLayout.offset(of: \task_vm_info_data_t.min_address)
      .map { mach_msg_type_number_t($0 / MemoryLayout<integer_t>.size) }
    let hasFootprint = result == KERN_SUCCESS && required.map { count >= $0 } == true
    let footprint = hasFootprint ? mebibytes(UInt64(info.phys_footprint)) : nil
    let resident = hasFootprint ? mebibytes(UInt64(info.resident_size)) : nil

    guard footprint != nil || available != nil else { return nil }
    var estimated: Int?
    if let footprint, let available {
      estimated = min(65_535, footprint + available)
    }
    return Snapshot(
      footprintMiB: footprint, residentMiB: resident,
      availableMiB: available, estimatedBudgetMiB: estimated
    )
    #else
    return nil
    #endif
  }

  private static func mebibytes(_ bytes: UInt64) -> Int {
    Int(min(65_535, bytes / 1_048_576))
  }
}
