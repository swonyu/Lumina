import Foundation
import SwiftData

// MARK: - User Profile
@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var gender: Gender
    var heightCm: Double
    var currentWeightKg: Double
    var goalWeightKg: Double?
    var experienceLevel: ExperienceLevel
    var primaryGoal: PrimaryGoal
    var workoutDaysPerWeek: Int
    var equipmentAccess: EquipmentAccess
    var dietaryPreferences: [DietaryPreference]
    var injuriesOrLimitations: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var goals: [Goal] = []

    init(
        name: String,
        age: Int,
        gender: Gender,
        heightCm: Double,
        currentWeightKg: Double,
        goalWeightKg: Double? = nil,
        experienceLevel: ExperienceLevel,
        primaryGoal: PrimaryGoal,
        workoutDaysPerWeek: Int,
        equipmentAccess: EquipmentAccess,
        dietaryPreferences: [DietaryPreference] = [],
        injuriesOrLimitations: String? = nil
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.heightCm = heightCm
        self.currentWeightKg = currentWeightKg
        self.goalWeightKg = goalWeightKg
        self.experienceLevel = experienceLevel
        self.primaryGoal = primaryGoal
        self.workoutDaysPerWeek = workoutDaysPerWeek
        self.equipmentAccess = equipmentAccess
        self.dietaryPreferences = dietaryPreferences
        self.injuriesOrLimitations = injuriesOrLimitations
    }
}

// MARK: - Enums
enum Gender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
}

enum ExperienceLevel: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

enum PrimaryGoal: String, Codable, CaseIterable {
    case loseFat = "Lose Fat"
    case buildMuscle = "Build Muscle"
    case improveStrength = "Improve Strength"
    case improveEndurance = "Improve Endurance"
    case generalHealth = "General Health & Fitness"
}

enum EquipmentAccess: String, Codable, CaseIterable {
    case fullGym = "Full Gym Access"
    case homeGym = "Home Gym (Dumbbells + Bench)"
    case minimal = "Minimal (Bodyweight + Resistance Bands)"
    case none = "No Equipment"
}

enum DietaryPreference: String, Codable, CaseIterable {
    case none = "No Restrictions"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case pescatarian = "Pescatarian"
    case keto = "Keto"
    case highProtein = "High Protein"
}

// MARK: - Body Metrics (Weight, Measurements over time)
@Model
final class BodyMetric {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double?
    var bodyFatPercentage: Double?
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var armsCm: Double?
    var thighsCm: Double?
    var notes: String?

    init(
        date: Date = Date(),
        weightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        hipsCm: Double? = nil,
        armsCm: Double? = nil,
        thighsCm: Double? = nil,
        notes: String? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.armsCm = armsCm
        self.thighsCm = thighsCm
        self.notes = notes
    }
}

// MARK: - Health Snapshot (from Apple Watch + manual input)
@Model
final class HealthSnapshot {
    var id: UUID = UUID()
    var date: Date = Date()
    
    // From HealthKit
    var restingHeartRate: Double?
    var heartRateVariability: Double?
    var sleepHours: Double?
    var activeEnergyBurned: Double?
    var exerciseMinutes: Double?
    
    // User-reported
    var energyLevel: Int?          // 1-10
    var sorenessLevel: Int?        // 1-10
    var mood: Mood?
    var notes: String?

    @Relationship
    var owner: UserProfile?

    init(date: Date = Date()) {
        self.date = date
    }
}

enum Mood: String, Codable, CaseIterable {
    case great = "Great"
    case good = "Good"
    case okay = "Okay"
    case low = "Low"
    case struggling = "Struggling"
}
