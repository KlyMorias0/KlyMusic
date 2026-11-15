import CoreAudio
import Foundation

func checked(_ status: OSStatus, _ operation: String) {
    guard status == noErr else { fatalError("\(operation): CoreAudio error \(status)") }
}

func stringProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    checked(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value), "Read audio string property")
    guard let value else { fatalError("Missing audio string property") }
    return value.takeRetainedValue() as String
}

var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var byteCount: UInt32 = 0
checked(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &byteCount), "List size")
var devices = [AudioObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioObjectID>.size)
checked(devices.withUnsafeMutableBytes {
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &byteCount, $0.baseAddress!)
}, "List devices")
var selected: AudioObjectID?
for device in devices {
    let name = stringProperty(device, kAudioObjectPropertyName)
    print("Audio device \(device): \(name)")
    if name == "BlackHole 2ch" { selected = device }
}
guard var device = selected else { fatalError("BlackHole 2ch is not registered") }
for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
                 kAudioHardwarePropertyDefaultSystemOutputDevice] {
    var address = AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    checked(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                      UInt32(MemoryLayout<AudioObjectID>.size), &device), "Set default route")
}
let uid = stringProperty(device, kAudioDevicePropertyDeviceUID)
guard !uid.isEmpty else { fatalError("BlackHole device UID is empty") }
try uid.write(toFile: "build-tests/ci-audio-device-uid.txt", atomically: true, encoding: .utf8)
print("CI input, output and system audio routed through BlackHole 2ch")
