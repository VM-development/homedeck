import HubCore
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit
import AenoKit

/// Every device HomeDeck knows. A device session replaces its UnbuiltDevice with its own class.
enum DeviceRegistry {
    static let kinds: [DeviceKind] = [
        DeviceKind(id: "walkingpad-c2", name: "WalkingPad C2", symbol: "figure.walk", link: .bluetooth,
                   featuresURL: WalkingPadCatalog.featuresURL) { WalkingPadDevice() },
        DeviceKind(id: "mi-scale-s400", name: "Mi Body Composition Scale S400", symbol: "scalemass", link: .bluetooth,
                   featuresURL: MiScaleCatalog.featuresURL) { MiScaleDevice() },
        DeviceKind(id: "philips-ac2729", name: "Philips 2000i AC2729", symbol: "humidifier", link: .wifi,
                   featuresURL: PhilipsAirCatalog.featuresURL) { PhilipsAirDevice() },
        DeviceKind(id: "zeppelin-pro", name: "Zeppelin Pro Edition", symbol: "hifispeaker", link: .wifi,
                   featuresURL: ZeppelinCatalog.featuresURL) { ZeppelinDevice() },
        DeviceKind(id: "xiaomi-fan-2-pro", name: "Xiaomi Standing Fan 2 Pro", symbol: "fan.floor", link: .wifi,
                   featuresURL: XiaomiFanCatalog.featuresURL) { XiaomiFanDevice() },
        DeviceKind(id: "dreame-l40-ultra", name: "Dreame L40 Ultra", symbol: "circle.circle", link: .wifi,
                   featuresURL: DreameCatalog.featuresURL) { DreameDevice() },
        DeviceKind(id: "aeno-ek7s", name: "AENO EK7S Kettle", symbol: "cup.and.saucer", link: .bluetooth,
                   featuresURL: AenoCatalog.featuresURL) { UnbuiltDevice(name: "AENO EK7S Kettle") },
    ]
}
