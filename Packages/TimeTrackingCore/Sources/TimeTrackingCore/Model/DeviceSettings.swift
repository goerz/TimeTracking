// DeviceSettings: device settings in the App Group's `UserDefaults` suite
// (spec_data_and_sync.md §1.6).

public import Foundation

/// Device settings: the App Group's `UserDefaults` suite, values as JSON.
public struct DeviceSettings: Sendable {
    private let suite: AppGroupDefaults

    public init(defaults: UserDefaults) {
        self.suite = AppGroupDefaults(defaults: defaults)
    }

    /// The App Group suite of `identity`, or the standard defaults.
    public init(identity: AppIdentity?) {
        self.suite = AppGroupDefaults(identity: identity)
    }

    private var defaults: UserDefaults {
        suite.defaults
    }

    public subscript<Value>(key: DeviceSettingKey<Value>) -> Value {
        get {
            guard let data = defaults.data(forKey: key.name),
                  let value = try? JSONDecoder().decode(Value.self, from: data)
            else {
                return key.defaultValue
            }
            return value
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key.name)
        }
    }

    /// The `deviceID` device setting, created on first use.
    public var deviceID: DeviceID {
        if let string = defaults.string(forKey: "deviceID"), let id = DeviceID(string) {
            return id
        }
        let id = DeviceID()
        defaults.set(id.rawValue, forKey: "deviceID")
        return id
    }
}
