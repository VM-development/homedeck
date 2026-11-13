/// Finds devices that took the earbuds while this iPhone was already connected.
public enum TakeoverDetector {
    /// Names of devices other than this iPhone that were not connected in `previous` and are in `current`,
    /// provided this iPhone is connected in both lists.
    public static func newcomers(previous: [PairedDevice], current: [PairedDevice], thisPhoneName: String?) -> [String] {
        guard let me = thisPhoneName,
              previous.first(where: { $0.name == me })?.isConnected == true,
              current.first(where: { $0.name == me })?.isConnected == true else { return [] }
        let wasConnected = Set(previous.filter(\.isConnected).map(\.name))
        return current.filter { $0.isConnected && $0.name != me && !wasConnected.contains($0.name) }.map(\.name)
    }
}
