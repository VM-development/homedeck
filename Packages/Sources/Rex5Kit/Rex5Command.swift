/// Noble custom GAIA commands used by the app. IDs from Noble FoKus Android 1.9.5 (`CustomCommands`),
/// confirmed on a Rex5 unless the case comment says otherwise.
// ponytail: only commands the app sends. Case battery (0x0317) always reads 0xFF; connect (0x0329) gets no reply and does nothing;
// EQ (0x0E01) is refused as not supported, so the EQ uses Qualcomm's Music Processing instead (see MusicProcessing).
public enum Rex5Command: UInt16, CaseIterable, Sendable {
    case leftBattery = 0x0306
    case rightBattery = 0x0307
    case firmwareVersion = 0x0309
    case setANCMode = 0x0314        // 1 byte, see ANCMode; never acknowledged
    case getANCMode = 0x0315        // replies status, then the mode
    case disconnectDevice = 0x032A  // no acknowledgement
    case deviceList = 0x032C        // answered by one unacknowledged packet per device
}
