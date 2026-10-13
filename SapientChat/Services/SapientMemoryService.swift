// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Darwin
import Sapient

/// `MemoryService` backed by SAPIENT's readings, iOS `phys_footprint` (what
/// the per-app limit is enforced against) and `os_proc_available_memory`,
/// corrected for memory-mapped model files.
///
/// Mapped GGUF weights aren't in the footprint, so `os_proc_available_memory`
/// kept saying there was room while they filled the phone: SapientChat was
/// ended for "vm-pageshortage" at ~6.3 GB resident with only ~3.9 GB of
/// footprint. Counting them against the allowance makes the memory plan
/// release idle models before that point instead.
nonisolated struct SapientMemoryService: MemoryService {
    func status() -> MemoryStatus {
        let mapped = Self.mappedFileBytes()
        let available = availableMemoryBytes().map { allowance in
            let held = mapped ?? 0
            return allowance > held ? allowance - held : 0
        }
        return MemoryStatus(footprintBytes: memoryFootprintBytes(), availableBytes: available, mappedBytes: mapped)
    }

    /// Resident file-backed memory of this process (`task_vm_info.external`).
    static func mappedFileBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.external) : nil
    }
}
