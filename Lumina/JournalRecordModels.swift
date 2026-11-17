import Foundation
import SwiftData
import CryptoKit

/// Explicit value projection. No selected file is opened as a SwiftData store.
@MainActor
enum JournalRecordModels {
    static func captureTrustedSnapshot(_ file: URL, limits: JournalTransferLimits, budget: JournalTransferBudget) async throws -> [JournalRecoveryRecord] {
        let schema = Schema(LuminaApp.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: file, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        defer { withExtendedLifetime(container) {} }
        return try await capture(container.mainContext, limits: limits, budget: budget)
    }

    static func capture(_ context: ModelContext, limits: JournalTransferLimits, budget: JournalTransferBudget) async throws -> [JournalRecoveryRecord] {
        var records: [JournalRecoveryRecord] = []
        var photoBytes = 0, payloadBytes = 0
        try await append(Item.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(UserProfile.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(BodyMetric.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(HealthSnapshot.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(Milestone.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(ProgressPhoto.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(Streak.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(MealLog.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(DailyCheckIn.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(WorkoutLog.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(JournalEntry.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(CoachMemoryEntry.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(Goal.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        try await append(Habit.self, context: context, records: &records, photoBytes: &photoBytes, payloadBytes: &payloadBytes, limits: limits, budget: budget, project: project)
        // Item has no stored UUID. Its content and duplicate ordinal identify the export row only.
        let itemIndices = records.indices.filter { records[$0].kind == .item }.sorted { records[$0].id < records[$1].id }
        var duplicates: [String: Int] = [:]
        for index in itemIndices {
            let key = records[index].id; let ordinal = duplicates[key, default: 0]
            duplicates[key] = ordinal + 1; records[index].id = key + ":" + String(ordinal)
        }
        records.sort { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
        // These values came only from our own immutable SwiftData snapshot.
        // The export worker validates the complete portable schema and photo
        // metadata before writing recovery tables or publishing a finished file.
        // Avoid repeating ImageIO/JSON validation on the UI actor.
        try budget.check()
        return records
    }

    private static func append<T: PersistentModel>(_ type: T.Type, context: ModelContext, records: inout [JournalRecoveryRecord], photoBytes: inout Int, payloadBytes: inout Int, limits: JournalTransferLimits, budget: JournalTransferBudget, project: (T) throws -> JournalRecoveryRecord) async throws {
        let count = try context.fetchCount(FetchDescriptor<T>())
        guard count <= limits.maximumRecords - records.count else { throw JournalTransferError.tooLarge }
        var descriptor = FetchDescriptor<T>(); descriptor.fetchLimit = limits.maximumRecords + 1
        let models = try context.fetch(descriptor)
        guard models.count == count else { throw JournalTransferError.changed }
        for (index, model) in models.enumerated() {
            try budget.check(); try Task.checkCancellation()
            let record = try project(model)
            let bytes = record.photo?.count ?? 0
            let encodedBytes = try record.payload(limits: limits).count
            guard bytes <= limits.maximumPhotoBytes,
                  bytes <= limits.maximumTotalPhotoBytes - photoBytes,
                  encodedBytes <= limits.maximumTotalRecordBytes - payloadBytes else { throw JournalTransferError.tooLarge }
            photoBytes += bytes; payloadBytes += encodedBytes; records.append(record)
            if index % 8 == 7 { await Task.yield() }
        }
    }

    private static func project(_ model: Item) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["timestamp"] = JournalRecoveryRecord.bits(model.timestamp.timeIntervalSinceReferenceDate)
        fields["title"] = model.title
        fields["note"] = model.note
        fields["isPinned"] = model.isPinned ? "1" : "0"
        fields["isComplete"] = model.isComplete ? "1" : "0"
        fields["accentName"] = model.accentName
        let id = SHA256.hash(data: try JSONEncoder.sortedRecovery.encode(fields)).map { String(format: "%02x", $0) }.joined()
        return JournalRecoveryRecord(kind: .item, id: id, fields: fields, ownerID: nil, photo: nil)
    }

    private static func project(_ model: UserProfile) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["name"] = model.name
        fields["age"] = String(model.age)
        fields["gender"] = model.gender.rawValue
        fields["heightCm"] = JournalRecoveryRecord.bits(model.heightCm)
        fields["currentWeightKg"] = JournalRecoveryRecord.bits(model.currentWeightKg)
        fields["goalWeightKg"] = model.goalWeightKg.map { JournalRecoveryRecord.bits($0) }
        fields["experienceLevel"] = model.experienceLevel.rawValue
        fields["primaryGoal"] = model.primaryGoal.rawValue
        fields["workoutDaysPerWeek"] = String(model.workoutDaysPerWeek)
        fields["equipmentAccess"] = model.equipmentAccess.rawValue
        fields["dietaryPreferences"] = try JournalRecoveryRecord.encodeList(model.dietaryPreferences.map(\.rawValue))
        fields["injuriesOrLimitations"] = model.injuriesOrLimitations.map { $0 }
        fields["createdAt"] = JournalRecoveryRecord.bits(model.createdAt.timeIntervalSinceReferenceDate)
        fields["updatedAt"] = JournalRecoveryRecord.bits(model.updatedAt.timeIntervalSinceReferenceDate)
        fields["goalIDs"] = try JournalRecoveryRecord.encodeList(model.goals.map { $0.id.uuidString }.sorted())
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .profile, id: id, fields: fields, ownerID: nil, photo: nil)
    }

    private static func project(_ model: BodyMetric) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["weightKg"] = model.weightKg.map { JournalRecoveryRecord.bits($0) }
        fields["bodyFatPercentage"] = model.bodyFatPercentage.map { JournalRecoveryRecord.bits($0) }
        fields["chestCm"] = model.chestCm.map { JournalRecoveryRecord.bits($0) }
        fields["waistCm"] = model.waistCm.map { JournalRecoveryRecord.bits($0) }
        fields["hipsCm"] = model.hipsCm.map { JournalRecoveryRecord.bits($0) }
        fields["armsCm"] = model.armsCm.map { JournalRecoveryRecord.bits($0) }
        fields["thighsCm"] = model.thighsCm.map { JournalRecoveryRecord.bits($0) }
        fields["notes"] = model.notes.map { $0 }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .bodyMetric, id: id, fields: fields, ownerID: nil, photo: nil)
    }

    private static func project(_ model: HealthSnapshot) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["restingHeartRate"] = model.restingHeartRate.map { JournalRecoveryRecord.bits($0) }
        fields["heartRateVariability"] = model.heartRateVariability.map { JournalRecoveryRecord.bits($0) }
        fields["sleepHours"] = model.sleepHours.map { JournalRecoveryRecord.bits($0) }
        fields["activeEnergyBurned"] = model.activeEnergyBurned.map { JournalRecoveryRecord.bits($0) }
        fields["exerciseMinutes"] = model.exerciseMinutes.map { JournalRecoveryRecord.bits($0) }
        fields["energyLevel"] = model.energyLevel.map { String($0) }
        fields["sorenessLevel"] = model.sorenessLevel.map { String($0) }
        fields["mood"] = model.mood.map { $0.rawValue }
        fields["notes"] = model.notes.map { $0 }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .healthSnapshot, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: Milestone) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["title"] = model.title
        fields["detail"] = model.detail
        fields["achievedDate"] = model.achievedDate.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        fields["isAchieved"] = model.isAchieved ? "1" : "0"
        fields["category"] = model.category.rawValue
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .milestone, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: ProgressPhoto) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["weightAtTime"] = model.weightAtTime.map { JournalRecoveryRecord.bits($0) }
        fields["notes"] = model.notes.map { $0 }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .progressPhoto, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: model.photoData)
    }

    private static func project(_ model: Streak) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["type"] = model.type.rawValue
        fields["currentStreak"] = String(model.currentStreak)
        fields["longestStreak"] = String(model.longestStreak)
        fields["lastCheckIn"] = model.lastCheckIn.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .streak, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: MealLog) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["mealName"] = model.mealName
        fields["calories"] = model.calories.map { JournalRecoveryRecord.bits($0) }
        fields["protein"] = model.protein.map { JournalRecoveryRecord.bits($0) }
        fields["carbs"] = model.carbs.map { JournalRecoveryRecord.bits($0) }
        fields["fat"] = model.fat.map { JournalRecoveryRecord.bits($0) }
        fields["notes"] = model.notes.map { $0 }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .meal, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: model.photoData)
    }

    private static func project(_ model: DailyCheckIn) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["energyLevel"] = String(model.energyLevel)
        fields["sorenessLevel"] = String(model.sorenessLevel)
        fields["sleepQuality"] = String(model.sleepQuality)
        fields["stressLevel"] = String(model.stressLevel)
        fields["mood"] = model.mood.rawValue
        fields["journalNote"] = model.journalNote.map { $0 }
        fields["didTrain"] = model.didTrain ? "1" : "0"
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .checkIn, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: WorkoutLog) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["workoutName"] = model.workoutName
        fields["exercises"] = try JournalRecoveryRecord.encodeExercises(model.exercises)
        fields["perceivedExertion"] = model.perceivedExertion.map { String($0) }
        fields["notes"] = model.notes.map { $0 }
        fields["durationMinutes"] = model.durationMinutes.map { String($0) }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .workout, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: JournalEntry) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["title"] = model.title.map { $0 }
        fields["content"] = model.content
        fields["mood"] = model.mood.map { $0.rawValue }
        fields["tags"] = try JournalRecoveryRecord.encodeList(model.tags)
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .journal, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: CoachMemoryEntry) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["date"] = JournalRecoveryRecord.bits(model.date.timeIntervalSinceReferenceDate)
        fields["type"] = model.type.rawValue
        fields["content"] = model.content
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .memory, id: id, fields: fields, ownerID: nil, photo: nil)
    }

    private static func project(_ model: Goal) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        fields["name"] = model.name
        fields["currentValue"] = JournalRecoveryRecord.bits(model.currentValue)
        fields["targetValue"] = JournalRecoveryRecord.bits(model.targetValue)
        fields["unit"] = model.unit
        fields["category"] = model.category
        fields["lastAdjustedByCoach"] = model.lastAdjustedByCoach.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        fields["adjustmentNotes"] = model.adjustmentNotes.map { $0 }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .goal, id: id, fields: fields, ownerID: model.owner?.id.uuidString, photo: nil)
    }

    private static func project(_ model: Habit) throws -> JournalRecoveryRecord {
        var fields: [String: String] = [:]
        let undo = model.journalRecoveryUndo
        fields["name"] = model.name
        fields["createdAt"] = JournalRecoveryRecord.bits(model.createdAt.timeIntervalSinceReferenceDate)
        fields["isActive"] = model.isActive ? "1" : "0"
        fields["currentStreak"] = String(model.currentStreak)
        fields["bestStreak"] = String(model.bestStreak)
        fields["totalCompletions"] = String(model.totalCompletions)
        fields["lastCompletedDate"] = model.lastCompletedDate.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        fields["coachSuggested"] = model.coachSuggested ? "1" : "0"
        fields["coachNotes"] = model.coachNotes.map { $0 }
        fields["targetFrequencyPerWeek"] = String(model.targetFrequencyPerWeek)
        fields["undoCompletionDate"] = undo.undoCompletionDate.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        fields["undoPreviousCompletionDate"] = undo.undoPreviousCompletionDate.map { JournalRecoveryRecord.bits($0.timeIntervalSinceReferenceDate) }
        fields["undoPreviousStreak"] = undo.undoPreviousStreak.map { String($0) }
        fields["undoPreviousBestStreak"] = undo.undoPreviousBestStreak.map { String($0) }
        fields["undoPreviousTotalCompletions"] = undo.undoPreviousTotalCompletions.map { String($0) }
        let id = model.id.uuidString
        return JournalRecoveryRecord(kind: .habit, id: id, fields: fields, ownerID: nil, photo: nil)
    }

    static func insert(_ records: [JournalPreparedRecord], into context: ModelContext,
                       budget: JournalTransferBudget) throws {
        var profiles: [String: UserProfile] = [:]
        for prepared in records where prepared.record.kind == .profile {
            try budget.check()
            let record = prepared.record
            let model = try profile(record, dietaryPreferences: prepared.list("dietaryPreferences")); context.insert(model); profiles[record.id] = model
        }
        for prepared in records where prepared.record.kind != .profile {
            try budget.check()
            let record = prepared.record
            switch record.kind {
            case .item:
                let model = try item(record)
                context.insert(model)
            case .bodyMetric:
                let model = try bodyMetric(record)
                context.insert(model)
            case .healthSnapshot:
                let model = try healthSnapshot(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .milestone:
                let model = try milestone(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .progressPhoto:
                let model = try progressPhoto(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .streak:
                let model = try streak(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .meal:
                let model = try meal(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .checkIn:
                let model = try checkIn(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .workout:
                guard let exercises = prepared.exercises else { throw JournalTransferError.invalid }
                let model = try workout(record, exercises: exercises)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .journal:
                let model = try journal(record, tags: prepared.list("tags"))
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .memory:
                let model = try memory(record)
                context.insert(model)
            case .goal:
                let model = try goal(record)
                if let ownerID = record.ownerID {
                    guard let owner = profiles[ownerID] else { throw JournalTransferError.invalid }
                    model.owner = owner
                }
                context.insert(model)
            case .habit:
                let model = try habit(record)
                context.insert(model)
            case .profile: break
            }
        }
        for prepared in records where prepared.record.kind == .profile {
            try budget.check()
            let record = prepared.record
            guard let profile = profiles[record.id], Set(profile.goals.map { $0.id.uuidString }) == Set(try prepared.list("goalIDs")) else { throw JournalTransferError.invalid }
        }
    }

    private static func item(_ record: JournalRecoveryRecord) throws -> Item {
        let model = Item()
        model.timestamp = try record.date("timestamp")
        model.title = try record.text("title")
        model.note = try record.text("note")
        model.isPinned = try record.boolean("isPinned")
        model.isComplete = try record.boolean("isComplete")
        model.accentName = try record.text("accentName")
        return model
    }

    private static func profile(_ record: JournalRecoveryRecord, dietaryPreferences: [String]) throws -> UserProfile {
        let model = UserProfile(name: "", age: 0, gender: .other, heightCm: 0, currentWeightKg: 0, experienceLevel: .beginner, primaryGoal: .generalHealth, workoutDaysPerWeek: 0, equipmentAccess: .none)
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.name = try record.text("name")
        model.age = try record.integer("age")
        model.gender = try record.enumValue(Gender.self, "gender")
        model.heightCm = try record.number("heightCm")
        model.currentWeightKg = try record.number("currentWeightKg")
        model.goalWeightKg = try record.fields["goalWeightKg"].map { _ in try record.number("goalWeightKg") }
        model.experienceLevel = try record.enumValue(ExperienceLevel.self, "experienceLevel")
        model.primaryGoal = try record.enumValue(PrimaryGoal.self, "primaryGoal")
        model.workoutDaysPerWeek = try record.integer("workoutDaysPerWeek")
        model.equipmentAccess = try record.enumValue(EquipmentAccess.self, "equipmentAccess")
        model.dietaryPreferences = try dietaryPreferences.map { raw in try JournalRecoveryRecord.requireEnum(DietaryPreference.self, raw) }
        model.injuriesOrLimitations = record.fields["injuriesOrLimitations"]
        model.createdAt = try record.date("createdAt")
        model.updatedAt = try record.date("updatedAt")
        return model
    }

    private static func bodyMetric(_ record: JournalRecoveryRecord) throws -> BodyMetric {
        let model = BodyMetric()
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.weightKg = try record.fields["weightKg"].map { _ in try record.number("weightKg") }
        model.bodyFatPercentage = try record.fields["bodyFatPercentage"].map { _ in try record.number("bodyFatPercentage") }
        model.chestCm = try record.fields["chestCm"].map { _ in try record.number("chestCm") }
        model.waistCm = try record.fields["waistCm"].map { _ in try record.number("waistCm") }
        model.hipsCm = try record.fields["hipsCm"].map { _ in try record.number("hipsCm") }
        model.armsCm = try record.fields["armsCm"].map { _ in try record.number("armsCm") }
        model.thighsCm = try record.fields["thighsCm"].map { _ in try record.number("thighsCm") }
        model.notes = record.fields["notes"]
        return model
    }

    private static func healthSnapshot(_ record: JournalRecoveryRecord) throws -> HealthSnapshot {
        let model = HealthSnapshot()
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.restingHeartRate = try record.fields["restingHeartRate"].map { _ in try record.number("restingHeartRate") }
        model.heartRateVariability = try record.fields["heartRateVariability"].map { _ in try record.number("heartRateVariability") }
        model.sleepHours = try record.fields["sleepHours"].map { _ in try record.number("sleepHours") }
        model.activeEnergyBurned = try record.fields["activeEnergyBurned"].map { _ in try record.number("activeEnergyBurned") }
        model.exerciseMinutes = try record.fields["exerciseMinutes"].map { _ in try record.number("exerciseMinutes") }
        model.energyLevel = try record.fields["energyLevel"].map { _ in try record.integer("energyLevel") }
        model.sorenessLevel = try record.fields["sorenessLevel"].map { _ in try record.integer("sorenessLevel") }
        model.mood = try record.fields["mood"].map { try JournalRecoveryRecord.requireEnum(Mood.self, $0) }
        model.notes = record.fields["notes"]
        return model
    }

    private static func milestone(_ record: JournalRecoveryRecord) throws -> Milestone {
        let model = Milestone(title: "", description: "", category: .consistency)
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.title = try record.text("title")
        model.detail = try record.text("detail")
        model.achievedDate = try record.fields["achievedDate"].map { _ in try record.date("achievedDate") }
        model.isAchieved = try record.boolean("isAchieved")
        model.category = try record.enumValue(MilestoneCategory.self, "category")
        return model
    }

    private static func progressPhoto(_ record: JournalRecoveryRecord) throws -> ProgressPhoto {
        let model = ProgressPhoto()
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.weightAtTime = try record.fields["weightAtTime"].map { _ in try record.number("weightAtTime") }
        model.notes = record.fields["notes"]
        model.photoData = record.photo
        return model
    }

    private static func streak(_ record: JournalRecoveryRecord) throws -> Streak {
        let model = Streak(type: .checkIn)
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.type = try record.enumValue(StreakType.self, "type")
        model.currentStreak = try record.integer("currentStreak")
        model.longestStreak = try record.integer("longestStreak")
        model.lastCheckIn = try record.fields["lastCheckIn"].map { _ in try record.date("lastCheckIn") }
        return model
    }

    private static func meal(_ record: JournalRecoveryRecord) throws -> MealLog {
        let model = MealLog(mealName: "")
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.mealName = try record.text("mealName")
        model.calories = try record.fields["calories"].map { _ in try record.number("calories") }
        model.protein = try record.fields["protein"].map { _ in try record.number("protein") }
        model.carbs = try record.fields["carbs"].map { _ in try record.number("carbs") }
        model.fat = try record.fields["fat"].map { _ in try record.number("fat") }
        model.notes = record.fields["notes"]
        model.photoData = record.photo
        return model
    }

    private static func checkIn(_ record: JournalRecoveryRecord) throws -> DailyCheckIn {
        let model = DailyCheckIn(energyLevel: 1, sorenessLevel: 1, sleepQuality: 1, stressLevel: 1, mood: .okay)
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.energyLevel = try record.integer("energyLevel")
        model.sorenessLevel = try record.integer("sorenessLevel")
        model.sleepQuality = try record.integer("sleepQuality")
        model.stressLevel = try record.integer("stressLevel")
        model.mood = try record.enumValue(Mood.self, "mood")
        model.journalNote = record.fields["journalNote"]
        model.didTrain = try record.boolean("didTrain")
        return model
    }

    private static func workout(_ record: JournalRecoveryRecord, exercises: [JournalPortableExercise]) throws -> WorkoutLog {
        let model = WorkoutLog(workoutName: "")
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.workoutName = try record.text("workoutName")
        model.exercises = try record.decodedExercises(exercises)
        model.perceivedExertion = try record.fields["perceivedExertion"].map { _ in try record.integer("perceivedExertion") }
        model.notes = record.fields["notes"]
        model.durationMinutes = try record.fields["durationMinutes"].map { _ in try record.integer("durationMinutes") }
        return model
    }

    private static func journal(_ record: JournalRecoveryRecord, tags: [String]) throws -> JournalEntry {
        let model = JournalEntry(content: "")
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.title = record.fields["title"]
        model.content = try record.text("content")
        model.mood = try record.fields["mood"].map { try JournalRecoveryRecord.requireEnum(Mood.self, $0) }
        model.tags = tags
        return model
    }

    private static func memory(_ record: JournalRecoveryRecord) throws -> CoachMemoryEntry {
        let model = CoachMemoryEntry(type: .reflection, content: "")
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.date = try record.date("date")
        model.type = try record.enumValue(MemoryType.self, "type")
        model.content = try record.text("content")
        return model
    }

    private static func goal(_ record: JournalRecoveryRecord) throws -> Goal {
        let model = Goal(name: "", targetValue: 1)
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.name = try record.text("name")
        model.currentValue = try record.number("currentValue")
        model.targetValue = try record.number("targetValue")
        model.unit = try record.text("unit")
        model.category = try record.text("category")
        model.lastAdjustedByCoach = try record.fields["lastAdjustedByCoach"].map { _ in try record.date("lastAdjustedByCoach") }
        model.adjustmentNotes = record.fields["adjustmentNotes"]
        return model
    }

    private static func habit(_ record: JournalRecoveryRecord) throws -> Habit {
        let model = Habit(name: "")
        guard let id = UUID(uuidString: record.id) else { throw JournalTransferError.invalid }; model.id = id
        model.name = try record.text("name")
        model.createdAt = try record.date("createdAt")
        model.isActive = try record.boolean("isActive")
        model.currentStreak = try record.integer("currentStreak")
        model.bestStreak = try record.integer("bestStreak")
        model.totalCompletions = try record.integer("totalCompletions")
        model.lastCompletedDate = try record.fields["lastCompletedDate"].map { _ in try record.date("lastCompletedDate") }
        model.coachSuggested = try record.boolean("coachSuggested")
        model.coachNotes = record.fields["coachNotes"]
        model.targetFrequencyPerWeek = try record.integer("targetFrequencyPerWeek")
        try model.applyJournalRecoveryUndo(record)
        return model
    }

}
