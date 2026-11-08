// HardwareUUID: this Mac's hardware UUID, its device id in the tracker's
// Samples and in `blocks/owner` (activity_tracking.md §2.2, §4.1).

#if os(macOS)
    import Foundation
    import IOKit

    /// The Mac's `IOPlatformUUID`, which stays when the Mac is renamed.
    public enum HardwareUUID {
        /// The UUID in lower case, or `nil` when IOKit doesn't give one.
        public static var current: String? {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
            guard service != 0 else {
                return nil
            }
            defer { IOObjectRelease(service) }
            let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
            return (value?.takeRetainedValue() as? String)?.lowercased()
        }
    }
#endif
