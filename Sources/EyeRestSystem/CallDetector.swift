import CoreAudio
import CoreMediaIO
import Foundation

/// Detects whether the user is probably on a call: some process is capturing from a camera or a microphone.
///
/// Only reads the system's "in use" flags, never audio or video, so it needs no permission. Every failure to read a
/// flag counts as "not in use".
public enum CallDetector {
    public static func isInCall() -> Bool {
        isCameraInUse() || isMicrophoneInUse()
    }

    /// True if any CoreMediaIO video device is running in any process.
    public static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == kCMIOHardwareNoError else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        guard !devices.isEmpty else { return false }
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == kCMIOHardwareNoError else {
            return false
        }
        return devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride).contains(where: isCameraRunningSomewhere)
    }

    /// True if any process other than this one is capturing audio input.
    ///
    /// Uses CoreAudio's per-process objects (macOS 14.2+; on earlier systems the list cannot be read and this returns
    /// false). Device-level "running somewhere" is not used: a headset such as AirPods reports it while only playing
    /// music.
    public static func isMicrophoneInUse() -> Bool {
        guard let processes = audioProcessObjects() else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processes.contains { process in
            guard let isRunningInput: UInt32 = audioProperty(kAudioProcessPropertyIsRunningInput, of: process),
                  isRunningInput != 0,
                  let pid: pid_t = audioProperty(kAudioProcessPropertyPID, of: process)
            else { return false }
            return pid != ownPID
        }
    }

    private static func isCameraRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var isRunning: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &isRunning) == kCMIOHardwareNoError else {
            return false
        }
        return isRunning != 0
    }

    /// The system's current list of audio process objects, or nil if it cannot be read.
    private static func audioProcessObjects() -> [AudioObjectID]? {
        var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == kAudioHardwareNoError else { return nil }
        var processes = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard !processes.isEmpty else { return [] }
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == kAudioHardwareNoError else {
            return nil
        }
        return Array(processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    /// Reads a fixed-size integer property of an audio object, or nil if the call fails.
    private static func audioProperty<Value: FixedWidthInteger>(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID
    ) -> Value? {
        var address = globalAddress(selector)
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == kAudioHardwareNoError,
              size == MemoryLayout<Value>.size
        else { return nil }
        return value
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
