import Foundation
import Observation
import WidgetKit
import Rex5Kit
import HubCore

/// Turns link events into the snapshot the app and widgets show, and runs the user's actions.
@MainActor
@Observable
final class EarbudService {
    private(set) var snapshot: EarbudSnapshot
    var notice: String?
    var showRoutePicker = false
    private(set) var isWorking = false

    let log: DeviceLogger
    private let link: EarbudLink
    private let notifier: TakeoverNotifier
    private let snapshotURL: URL?
    private var assembler = DeviceListAssembler()
    private var listGeneration = 0
    private var connectionListStart = 0
    private var keepBaseline = false
    private var debounce: Task<Void, Never>?
    private var widgetGate: WidgetReloadGate
    private var reloadPending = false
    private var batteryNudge: Task<Void, Never>?
    /// What the earbuds last reported; nil until read.
    private(set) var ancMode: ANCMode?
    /// The mode being switched to, until the earbuds confirm it.
    private(set) var ancPending: ANCMode?
    /// Goes up each time a switch is confirmed, for the checkmark and haptic.
    private(set) var ancConfirmation = 0
    private var ancRequest = 0
    /// The earbuds' EQ as they report it (Qualcomm Music Processing); empty until read.
    private(set) var eqPresets: [UInt8] = []
    private(set) var eqSelected: UInt8?
    private(set) var eqBands: [MusicProcessing.Band] = []
    private(set) var eqSending = false
    /// Goes up each time an EQ change is accepted, for the checkmark and haptic.
    private(set) var eqConfirmation = 0
    private var eqQueued: EQChange?
    private enum EQChange { case preset(UInt8), gains([Int]) }

    var eqTitle: String? { eqSelected.map { MusicProcessing.title(of: $0, among: eqPresets) } }

    /// One instance for the app and for Shortcuts actions, which can start the app without opening a screen.
    static let shared = EarbudService(link: EarbudLink(), log: ConnectionLog.shared.tagged("rex5"), notifier: TakeoverNotifier(),
                                      snapshotURL: SnapshotFile.defaultURL)

    static let thisPhoneKey = "rex5.thisPhoneName"
    static let batteryMaxAge: TimeInterval = 10 * 60

    init(link: EarbudLink, log: DeviceLogger, notifier: TakeoverNotifier, snapshotURL: URL?) {
        self.link = link
        self.log = log
        self.notifier = notifier
        self.snapshotURL = snapshotURL
        let saved = snapshotURL.flatMap(SnapshotFile.read) ?? EarbudSnapshot()
        var initial = saved
        initial.link = .disconnected  // saved link status is stale; only a live link event may set .connected
        initial.thisPhoneName = UserDefaults.standard.string(forKey: Self.thisPhoneKey)
        snapshot = initial
        widgetGate = WidgetReloadGate(shown: saved)
        link.onLog = { [weak self] in self?.log.add($0) }
        link.onState = { [weak self] in self?.linkChanged($0) }
        link.onDevice = { [weak self] in self?.received($0) }
        link.onRestoredConnection = { [weak self] in self?.keepBaseline = true; self?.connectionListStart = -1 }
        link.onBatteryNotification = { [weak self] in self?.batteryNotified($0) }
        publish()  // the widgets may still show the link status saved before the app was closed
    }

    var suggestedThisPhone: String? { EarbudSnapshot.suggestedThisPhone(in: snapshot.devices) }
    var needsThisPhoneChoice: Bool { snapshot.thisPhoneName == nil && !snapshot.devices.isEmpty }

    func setThisPhone(_ name: String) {
        UserDefaults.standard.set(name, forKey: Self.thisPhoneKey)
        update { $0.thisPhoneName = name }
        log.add("This iPhone is \(name)")
        notifier.requestPermission()
    }

    func appBecameActive() async {
        link.checkAudio()
        await refreshBatteryIfStale(force: true)
    }

    /// For the "Refresh REX5" Shortcuts action, run by an automation when the earbuds connect:
    /// connect once the sound is up, read the battery, and give the widgets time to reload.
    func refreshFromShortcut() async {
        log.add("Shortcut: refreshing")
        link.checkAudio()
        let fresh = { self.snapshot.link == .connected && self.snapshot.batteryReadAt.map { Date().timeIntervalSince($0) < 20 } == true }
        if await waitUntil(seconds: 12, fresh) {
            try? await Task.sleep(for: .seconds(3))  // widget reloads are batched over 2 s
        } else {
            log.add("Shortcut: the earbuds didn't connect within 12 s")
        }
    }

    /// Reads battery and firmware, then asks for the device list (it arrives as separate packets).
    func refresh() async {
        guard snapshot.link == .connected else {
            link.checkAudio()  // pull to refresh while disconnected: try to connect instead of reading
            return
        }
        await readBattery()
        if snapshot.firmware == nil, let reply = try? await link.send(GaiaPacket(command: Rex5Command.firmwareVersion.rawValue)),
           reply.status == 0 {
            update { $0.firmware = String(decoding: reply.responseData, as: UTF8.self) }
        }
        requestDeviceList()
    }

    func connectThisPhone() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let start = listGeneration
        link.resume()
        // An app can't open the audio link, and the earbuds ignore "connect device" (0x0329, no reply on 2026-11-11).
        guard EarbudLink.audioIsUp else {
            showRoutePicker = true
            log.add("Connect: no Bluetooth sound, showed how to connect it")
            return
        }
        requestDeviceList()
        let worked = await waitUntil(seconds: 10) {
            self.listGeneration > start && self.snapshot.isConnectedHere
        }
        if worked {
            log.add("Connected this iPhone")
        } else {
            showRoutePicker = true
            log.add("Connect not confirmed within 10 s, opened the audio picker")
        }
    }

    func disconnectThisPhone() async {
        guard let me = snapshot.thisPhoneName else {
            notice = "Choose which device is this iPhone first."
            return
        }
        await disconnect(named: me, isThisPhone: true)
    }

    func disconnect(_ device: PairedDevice) async {
        await disconnect(named: device.name, isThisPhone: false)
    }

    /// Looks the device up in a fresh list (indexes change), tells the earbuds to drop it and waits to see it go.
    /// Dropping this iPhone also drops the link, so reconnecting is paused first.
    private func disconnect(named name: String, isThisPhone: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let label = isThisPhone ? "This iPhone" : name
        guard snapshot.link != .paused,
              await waitUntil(seconds: 10, { self.snapshot.link == .connected }) else {
            notice = "The earbuds aren't connected."
            return
        }
        guard let target = await freshEntry(named: name) else {
            notice = "Couldn't find \(isThisPhone ? "this iPhone" : name) in the earbuds' list."
            return
        }
        guard target.isConnected else {
            notice = "\(label) is already disconnected."
            return
        }
        if isThisPhone { link.pauseReconnect() }
        do {
            try link.sendWithoutReply(GaiaPacket(command: Rex5Command.disconnectDevice.rawValue, payload: [target.index]))
        } catch {
            if isThisPhone { link.resume() }
            notice = error.localizedDescription
            return
        }
        let gone = {
            isThisPhone ? self.snapshot.link == .paused || !self.snapshot.isThisPhoneConnected
                        : self.snapshot.devices.first { $0.name == name }?.isConnected == false
        }
        var worked = await waitUntil(seconds: 2.5, gone)
        if !worked {
            requestDeviceList()  // the earbuds don't always push the change
            worked = await waitUntil(seconds: 2.5, gone)
        }
        if worked {
            log.add("Disconnected \(label)")
        } else {
            if isThisPhone { link.resume() }
            notice = "No change seen."
            log.add("Disconnect \(label): no change seen")
        }
    }

    // MARK: - Link events

    /// Switches noise control. The earbuds never acknowledge the switch (2026-11-12), so it's confirmed by reading the mode back.
    func setANC(_ mode: ANCMode) async {
        guard snapshot.link == .connected else { return }
        ancRequest += 1
        let request = ancRequest
        ancPending = mode
        defer { if ancRequest == request { ancPending = nil } }
        do {
            try link.sendWithoutReply(mode.packet)
        } catch {
            log.add("ANC switch to \(mode.title): \(error.localizedDescription)")
            return
        }
        // ponytail: polls up to 2.4 s; the earbuds reported the new mode within a second in testing.
        for attempt in 1...8 {
            try? await Task.sleep(for: .milliseconds(300))
            guard ancRequest == request else { return }  // a newer tap took over
            if await readANC() == mode {
                log.add("ANC switched to \(mode.title), confirmed after \(attempt * 300) ms")
                ancConfirmation += 1
                return
            }
        }
        log.add("ANC didn't switch to \(mode.title); the earbuds report \(ancMode?.title ?? "nothing")")
        notice = "The earbuds didn't switch to \(mode.title). Try again."
    }

    @discardableResult
    func readANC() async -> ANCMode? {
        do {
            let reply = try await link.send(GaiaPacket(command: Rex5Command.getANCMode.rawValue), timeout: .seconds(1.5))
            if reply.status == 0, let mode = reply.responseData.first.flatMap(ANCMode.init(rawValue:)) {
                ancMode = mode
                return mode
            }
            log.add("ANC read reply \(reply.payload.hex)")
        } catch {
            log.add("ANC read: \(error.localizedDescription)")
        }
        return nil
    }

    /// Reads the presets, the selected one and the custom bands from the earbuds.
    func loadEQ() async {
        guard snapshot.link == .connected else { return }
        if let reply = await askEQ(MusicProcessing.packet(MusicProcessing.getPresets)) {
            eqPresets = MusicProcessing.presets(from: reply.payload)
        }
        if let reply = await askEQ(MusicProcessing.packet(MusicProcessing.getSelected)), let preset = reply.payload.first {
            eqSelected = preset
        }
        if let count = await askEQ(MusicProcessing.packet(MusicProcessing.getBandCount))?.payload.first, count > 0,
           let reply = await askEQ(MusicProcessing.packet(MusicProcessing.getBands, [0, count - 1])) {
            eqBands = MusicProcessing.bands(from: reply.payload)
        }
        log.add("EQ is \(eqTitle ?? "unknown"); custom bands " + eqBands.map { "\($0.frequency) Hz \(Int($0.gain.rounded())) dB" }.joined(separator: ", "))
    }

    func selectEQ(_ preset: UInt8) { queueEQ(.preset(preset)) }

    /// Custom gains in dB for every band; switches the earbuds to the custom set first.
    func setEQGains(_ gains: [Int]) { queueEQ(.gains(gains)) }

    /// Sends the latest change only: changes made while one is being sent replace each other.
    private func queueEQ(_ change: EQChange) {
        guard snapshot.link == .connected else { return }
        eqQueued = change
        guard !eqSending else { return }
        eqSending = true
        Task {
            var accepted = true
            while let next = eqQueued {
                eqQueued = nil
                accepted = await sendEQ(next)
            }
            eqSending = false
            if accepted { eqConfirmation += 1 } else { notice = "The earbuds didn't accept the EQ change." }
        }
    }

    private func sendEQ(_ change: EQChange) async -> Bool {
        switch change {
        case .preset(let preset):
            guard await askEQ(MusicProcessing.packet(MusicProcessing.setSelected, [preset])) != nil else { return false }
            eqSelected = preset
            log.add("EQ set to \(eqTitle ?? "\(preset)")")
            if preset == MusicProcessing.custom { return await writeBands(Array(eqBands.indices), eqBands.map { Int($0.gain.rounded()) }) }
        case .gains(let gains):
            // One band per write: a multi-band write is stored but the earbuds' DSP applies only its first band,
            // and reselecting Custom reloads defaults (both seen 2026-11-12).
            var bands = Array(gains.indices.filter { $0 >= eqBands.count || Int(eqBands[$0].gain.rounded()) != gains[$0] })
            if eqSelected != MusicProcessing.custom {
                guard await askEQ(MusicProcessing.packet(MusicProcessing.setSelected, [MusicProcessing.custom])) != nil else { return false }
                eqSelected = MusicProcessing.custom
                bands = Array(gains.indices)  // the DSP starts from the earbuds' own copy, so set every band
            }
            return await writeBands(bands, gains)
        }
        return true
    }

    /// Writes the given bands one at a time. Selecting Custom makes the earbuds' DSP start from their own copy,
    /// so callers re-send every band after a select.
    private func writeBands(_ bands: [Int], _ gains: [Int]) async -> Bool {
        for band in bands where gains.indices.contains(band) {
            guard await askEQ(MusicProcessing.gainsPacket([gains[band]], firstBand: band)) != nil else { return false }
            if eqBands.indices.contains(band) {
                eqBands[band].gain = Double(gains[band])
            }
        }
        if !bands.isEmpty {
            log.add("EQ custom bands " + bands.map { "\(eqBands.indices.contains($0) ? eqBands[$0].frequency : $0) Hz \(gains[$0])" }
                        .joined(separator: ", ") + " dB")
        }
        return true
    }

    /// Sends one Music Processing command; nil (and a log line) for a refusal or no reply.
    private func askEQ(_ packet: GaiaPacket) async -> GaiaPacket? {
        do {
            let reply = try await link.send(packet, timeout: .seconds(1.5))
            guard reply.command & 0x0180 != 0x0180 else {  // v3 error
                log.add(String(format: "EQ command 0x%04X refused, error ", packet.command) + reply.payload.hex)
                return nil
            }
            return reply
        } catch {
            log.add(String(format: "EQ command 0x%04X: ", packet.command) + error.localizedDescription)
            return nil
        }
    }

    private func linkChanged(_ state: EarbudLink.State) {
        log.add("Link: \(state)")
        switch state {
        case .ready:
            let restored = keepBaseline
            if keepBaseline { keepBaseline = false; connectionListStart = -1 } else { connectionListStart = listGeneration }
            update { $0.link = .connected }
            Task {
                await refresh()
                // The user wants ANC off by default (2026-11-12). A link iOS restored keeps whatever mode was chosen.
                if restored {
                    await readANC()
                } else {
                    log.add("New connection: turning ANC off")
                    await setANC(.off)
                }
                await loadEQ()
                if eqSelected == MusicProcessing.custom {  // the DSP starts from the earbuds' own copy after connecting
                    _ = await writeBands(Array(eqBands.indices), eqBands.map { Int($0.gain.rounded()) })
                }
            }
        case .connecting, .searching:
            update { $0.link = .connecting }
        case .notFound:
            update { $0.link = .notFound }
        case .paused:
            update { $0.link = .paused }
        case .waitingForAudio:
            update { $0.link = .disconnected }
        case .bluetoothOff(let reason):
            update { $0.link = .bluetoothOff }
            notice = reason
        }
    }

    private func received(_ device: PairedDevice) {
        assembler.add(device)
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.apply(self.assembler.devices)
        }
    }

    private func apply(_ devices: [PairedDevice]) {
        let previous = snapshot.devices
        if listGeneration > connectionListStart {
            for name in TakeoverDetector.newcomers(previous: previous, current: devices, thisPhoneName: snapshot.thisPhoneName) {
                notifier.post(deviceName: name)
                log.add("\(name) connected while this iPhone was connected")
            }
        }
        if devices != previous {
            log.add("Devices: " + devices.map { $0.isConnected ? "\($0.name) (connected)" : $0.name }.joined(separator: ", "))
        }
        update { $0.devices = devices }
        listGeneration += 1
        Task { await refreshBatteryIfStale(force: false) }
    }

    // MARK: - Helpers

    /// The earbuds' standard battery service reported a change; iOS wakes the app for this even in the background.
    /// Its value isn't per earbud, so it only triggers a read of both earbuds over GAIA.
    private func batteryNotified(_ level: UInt8) {
        batteryNudge?.cancel()
        batteryNudge = Task {
            try? await Task.sleep(for: .seconds(1))  // several updates can arrive together
            guard !Task.isCancelled else { return }
            log.add("Battery service reports \(level)%, reading both earbuds")
            await refreshBatteryIfStale(force: true)
        }
    }

    private func refreshBatteryIfStale(force: Bool) async {
        guard snapshot.link == .connected else { return }
        if !force, let readAt = snapshot.batteryReadAt, Date().timeIntervalSince(readAt) < Self.batteryMaxAge { return }
        await readBattery()
    }

    private func readBattery() async {
        let left = await readByte(.leftBattery)
        let right = await readByte(.rightBattery)
        guard left != nil || right != nil else { return }
        let percent = { (byte: UInt8) in byte <= 100 ? Int(byte) : nil }  // the earbuds send 0xFF for unknown
        update {
            if let left { $0.leftBattery = percent(left) }
            if let right { $0.rightBattery = percent(right) }
            $0.batteryReadAt = Date()
        }
    }

    private func readByte(_ command: Rex5Command) async -> UInt8? {
        do {
            let reply = try await link.send(GaiaPacket(command: command.rawValue))
            guard reply.status == 0, let byte = reply.responseData.first else {
                log.add("\(command) rejected with status \(reply.status.map { String($0) } ?? "none")")
                return nil
            }
            return byte
        } catch {
            log.add("\(command) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func requestDeviceList() {
        try? link.sendWithoutReply(GaiaPacket(command: Rex5Command.deviceList.rawValue))
    }

    /// The entry for `name` from a fresh device list, since the order changes.
    private func freshEntry(named name: String) async -> PairedDevice? {
        let start = listGeneration
        requestDeviceList()
        guard await waitUntil(seconds: 2, { self.listGeneration > start }) else { return nil }
        return snapshot.devices.first { $0.name == name }
    }

    private func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        // ponytail: 0.2 s polling for one-shot user actions; switch to continuations if it ever runs hot.
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    private func update(_ change: (inout EarbudSnapshot) -> Void) {
        let before = snapshot
        var next = snapshot
        change(&next)
        guard next != before else { return }
        next.updatedAt = Date()
        snapshot = next
        publish()
    }

    /// Saves the snapshot for the widgets and reloads them when they would look different.
    private func publish() {
        if let snapshotURL { try? SnapshotFile.write(snapshot, to: snapshotURL) }
        guard !reloadPending else { return }
        reloadPending = true
        // iOS caps background widget reloads per day (it ran out on 2026-11-11), so a burst such as
        // connecting → connected → battery costs one reload, judged on where the burst ends.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            reloadPending = false
            guard widgetGate.shouldReload(for: snapshot) else { return }
            WidgetCenter.shared.reloadAllTimelines()
            log.add("Widget refresh: \(snapshot.lockStatusLine), L \(snapshot.batteryText(snapshot.leftBattery)) R \(snapshot.batteryText(snapshot.rightBattery))")
        }
    }
}
