import HealthKit
import MiScaleKit

/// Writes weigh-ins to Apple Health. HomeDeck asks only to write, never to read.
enum HealthSaver {
    private static let store = HKHealthStore()
    private static let types: Set<HKSampleType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.bodyMassIndex), HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.leanBodyMass), HKQuantityType(.heartRate),
    ]

    /// True when the sheet was shown and weight writing is allowed.
    static func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do { try await store.requestAuthorization(toShare: types, read: []) } catch { return false }
        return store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized
    }

    static func save(_ weighIn: WeighIn, composition: BodyComposition?) async throws {
        var samples: [HKQuantitySample] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
            guard let value, store.authorizationStatus(for: HKQuantityType(id)) == .sharingAuthorized else { return }
            samples.append(HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: weighIn.date, end: weighIn.date))
        }
        add(.bodyMass, .gramUnit(with: .kilo), weighIn.weight)
        add(.bodyMassIndex, .count(), composition?.bmi)
        add(.bodyFatPercentage, .percent(), composition?.fatPercent.map { $0 / 100 })
        add(.leanBodyMass, .gramUnit(with: .kilo), composition?.leanMass)
        add(.heartRate, .count().unitDivided(by: .minute()), weighIn.heartRate.map(Double.init))
        try await store.save(samples)
    }
}
