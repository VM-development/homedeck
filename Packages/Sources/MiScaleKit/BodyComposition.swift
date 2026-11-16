import Foundation

/// Body composition estimated from weight, height, age, sex and the 50 kHz impedance, with published
/// bioimpedance equations. Xiaomi's own S400 formula isn't public, so Xiaomi Home's numbers can differ.
public struct BodyComposition: Equatable, Sendable {
    public let bmi: Double
    /// Nil without an impedance (weighed in socks).
    public let fatPercent: Double?
    public let leanMass: Double?
    public let waterPercent: Double?
    public let muscleMass: Double?
    public let boneMass: Double?

    public init(weight: Double, impedance: Double?, heightCM: Double, age: Int, male: Bool) {
        let metres = heightCM / 100
        bmi = weight / (metres * metres)
        guard let r = impedance, r > 0 else {
            fatPercent = nil; leanMass = nil; waterPercent = nil; muscleMass = nil; boneMass = nil
            return
        }
        let index = heightCM * heightCM / r  // height² / resistance, the core of every BIA equation
        // Fat-free mass and total body water: Sun et al. 2003, Am J Clin Nutr 77:331 (NHANES III).
        let ffm = male ? -10.678 + 0.262 * weight + 0.652 * index + 0.015 * r
                       : -9.529 + 0.168 * weight + 0.696 * index + 0.016 * r
        let water = male ? 1.203 + 0.176 * weight + 0.449 * index
                         : 3.747 + 0.113 * weight + 0.450 * index
        let lean = min(max(ffm, 0), weight)
        leanMass = lean
        fatPercent = (weight - lean) / weight * 100
        waterPercent = water / weight * 100
        // Skeletal muscle mass: Janssen et al. 2000, J Appl Physiol 89:465.
        muscleMass = index * 0.401 + (male ? 3.825 : 0) - 0.071 * Double(age) + 5.102
        // ponytail: bone mineral as 5% of lean mass, a rough population ratio; no BIA equation measures bone.
        boneMass = lean * 0.05
    }
}
