import HubCore
import Rex5Kit
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit

/// Every device HomeDeck knows. A device session replaces its UnbuiltDevice with its own class.
enum DeviceRegistry {
    static let kinds: [DeviceKind] = [
        DeviceKind(id: "rex5", name: "Noble FoKus Rex5", symbol: "earbuds", link: .bluetooth,
                   featuresURL: Rex5Catalog.featuresURL) { Rex5Device.shared },
        DeviceKind(id: "walkingpad-c2", name: "WalkingPad C2", symbol: "figure.walk", link: .bluetooth,
                   featuresURL: WalkingPadCatalog.featuresURL) { UnbuiltDevice(name: "WalkingPad C2") },
        DeviceKind(id: "mi-scale-s400", name: "Mi Body Composition Scale S400", symbol: "scalemass", link: .bluetooth,
                   featuresURL: MiScaleCatalog.featuresURL) { UnbuiltDevice(name: "Mi Body Composition Scale S400") },
        DeviceKind(id: "philips-ac2729", name: "Philips 2000i AC2729", symbol: "humidifier", link: .wifi,
                   featuresURL: PhilipsAirCatalog.featuresURL) { UnbuiltDevice(name: "Philips 2000i AC2729") },
        DeviceKind(id: "zeppelin-pro", name: "Zeppelin Pro Edition", symbol: "hifispeaker", link: .wifi,
                   featuresURL: ZeppelinCatalog.featuresURL) { UnbuiltDevice(name: "Zeppelin Pro Edition") },
        DeviceKind(id: "xiaomi-fan-2-pro", name: "Xiaomi Standing Fan 2 Pro", symbol: "fan.floor", link: .wifi,
                   featuresURL: XiaomiFanCatalog.featuresURL) { UnbuiltDevice(name: "Xiaomi Standing Fan 2 Pro") },
        DeviceKind(id: "dreame-l40-ultra", name: "Dreame L40 Ultra", symbol: "circle.circle", link: .wifi,
                   featuresURL: DreameCatalog.featuresURL) { UnbuiltDevice(name: "Dreame L40 Ultra") },
    ]
}
