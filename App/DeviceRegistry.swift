import HubCore
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit
import AenoKit

/// Every device HomeDeck knows; each one's details are in its kit's device.json.
/// A device session replaces its UnbuiltDevice with its own class.
enum DeviceRegistry {
    static let kinds: [DeviceKind] = [
        DeviceKind(manifest: WalkingPadCatalog.manifest) { WalkingPadDevice() },
        DeviceKind(manifest: MiScaleCatalog.manifest) { MiScaleDevice() },
        DeviceKind(manifest: PhilipsAirCatalog.manifest) { PhilipsAirDevice() },
        DeviceKind(manifest: ZeppelinCatalog.manifest) { ZeppelinDevice() },
        DeviceKind(manifest: XiaomiFanCatalog.manifest) { XiaomiFanDevice() },
        DeviceKind(manifest: DreameCatalog.manifest) { DreameDevice() },
        DeviceKind(manifest: AenoCatalog.manifest) { UnbuiltDevice(name: "AENO EK7S Kettle") },
    ]
}
