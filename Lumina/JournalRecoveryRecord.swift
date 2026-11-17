import Foundation
import CryptoKit
import ImageIO
import CoreGraphics

extension JSONEncoder {
    nonisolated static var sortedRecovery: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

nonisolated enum JournalRecordKind: String, Codable, CaseIterable, Sendable {
    case item, profile, bodyMetric, healthSnapshot, milestone, progressPhoto, streak
    case meal, checkIn, workout, journal, memory, goal, habit

    var labelKey: String {
        switch self {
        case .item: return "Ideas"
        case .profile: return "Profiles"
        case .bodyMetric: return "Body measurements"
        case .healthSnapshot: return "Health snapshots"
        case .milestone: return "Milestones"
        case .progressPhoto: return "Progress photos"
        case .streak: return "Streak records"
        case .meal: return "Meals"
        case .checkIn: return "Daily check-ins"
        case .workout: return "Workouts"
        case .journal: return "Journal entries"
        case .memory: return "Saved coaching notes"
        case .goal: return "Goals"
        case .habit: return "Habits"
        }
    }

    var permitsOwner: Bool {
        [.healthSnapshot, .milestone, .progressPhoto, .streak, .meal, .checkIn,
         .workout, .journal, .goal].contains(self)
    }
}

/// Version 1 uses a fixed kind and field schema. Scalar strings preserve exact
/// finite Double bits; only the two photo kinds may carry a separate binary blob.
/// No arbitrary Codable/SwiftData transformable is decoded from a selected file.
nonisolated struct JournalRecoveryRecord: Codable, Equatable, Sendable {
    var kind: JournalRecordKind
    var id: String
    var fields: [String: String]
    var ownerID: String?
    var photo: Data?

    enum CodingKeys: String, CodingKey { case kind, id, fields, ownerID }

    init(kind: JournalRecordKind, id: String, fields: [String: String], ownerID: String?, photo: Data?) {
        self.kind = kind; self.id = id; self.fields = fields; self.ownerID = ownerID; self.photo = photo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(JournalRecordKind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        fields = try container.decode([String: String].self, forKey: .fields)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
        photo = nil
    }

    func payload(limits: JournalTransferLimits) throws -> Data {
        let data = try JSONEncoder.sortedRecovery.encode(self)
        guard data.count <= limits.maximumRecordBytes else { throw JournalTransferError.tooLarge }
        return data
    }

    static func decode(_ data: Data, photo: Data?, limits: JournalTransferLimits,
                       budget: JournalTransferBudget? = nil) throws -> Self {
        try validateJSON(data, maximumBytes: limits.maximumRecordBytes, depth: 4)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["kind", "id", "fields", "ownerID"]),
              Set(["kind", "id", "fields"]).isSubset(of: Set(object.keys)) else {
            throw JournalTransferError.invalid
        }
        var record: Self
        do { record = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw JournalTransferError.invalid }
        record.photo = photo
        try record.validate(limits: limits, budget: budget)
        return record
    }

    func text(_ key: String) throws -> String {
        guard let value = fields[key] else { throw JournalTransferError.invalid }
        return value
    }
    func integer(_ key: String) throws -> Int {
        let value = try text(key)
        guard let result = Int(value), String(result) == value else { throw JournalTransferError.invalid }
        return result
    }
    func number(_ key: String) throws -> Double {
        let value = try text(key)
        guard value.count == 16, value.allSatisfy({ $0.isASCII && ("0123456789abcdef".contains($0)) }),
              let pattern = UInt64(value, radix: 16) else { throw JournalTransferError.invalid }
        let result = Double(bitPattern: pattern)
        guard result.isFinite else { throw JournalTransferError.invalid }
        return result
    }
    func date(_ key: String) throws -> Date {
        let value = try number(key)
        // Version1 declares the2001 Swift reference epoch in its header. Store
        // the existing Date's exact Double bits, without epoch-offset rounding.
        guard (-63_113_904_000...252_423_993_599).contains(value) else { throw JournalTransferError.invalid }
        return Date(timeIntervalSinceReferenceDate: value)
    }
    func boolean(_ key: String) throws -> Bool {
        let value = try text(key)
        guard value == "0" || value == "1" else { throw JournalTransferError.invalid }
        return value == "1"
    }
    func stringList(_ key: String) throws -> [String] {
        let data = Data(try text(key).utf8)
        try Self.validateJSON(data, maximumBytes: 1_024 * 1_024, depth: 1)
        do { return try JSONDecoder().decode([String].self, from: data) }
        catch { throw JournalTransferError.invalid }
    }
    static func bits(_ value: Double) -> String { String(format: "%016llx", value.bitPattern) }
    static func encodeList(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder.sortedRecovery.encode(values), as: UTF8.self)
    }

    static func validateJSON(_ data: Data, maximumBytes: Int, depth maximumDepth: Int) throws {
        guard data.count <= maximumBytes else { throw JournalTransferError.tooLarge }
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 91 || byte == 123 {
                depth += 1; guard depth <= maximumDepth else { throw JournalTransferError.invalid }
            } else if byte == 93 || byte == 125 {
                depth -= 1; guard depth >= 0 else { throw JournalTransferError.invalid }
            }
        }
        guard depth == 0, !quoted else { throw JournalTransferError.invalid }
    }

    func validate(limits: JournalTransferLimits, budget: JournalTransferBudget? = nil) throws {
        try budget?.check()
        guard fields.count <= 32, id.utf8.count <= 80 else { throw JournalTransferError.invalid }
        if kind == .item {
            guard id.range(of: #"^[0-9a-f]{64}(?::[0-9]{1,6})?$"#, options: .regularExpression) != nil else {
                throw JournalTransferError.invalid
            }
        } else { try Self.requireUUID(id) }
        if let ownerID {
            guard kind.permitsOwner else { throw JournalTransferError.invalid }
            try Self.requireUUID(ownerID)
        }
        if let photo {
            guard kind == .meal || kind == .progressPhoto else { throw JournalTransferError.invalid }
            guard photo.count <= limits.maximumPhotoBytes else { throw JournalTransferError.tooLarge }
            try Self.validatePhoto(photo, limits: limits, budget: budget)
        }
        let schema = Self.schema(kind)
        guard Set(fields.keys).isSubset(of: Set(schema.keys)),
              schema.allSatisfy({ $0.value.optional || fields[$0.key] != nil }) else { throw JournalTransferError.invalid }
        for (key, value) in fields {
            guard key.utf8.count <= 64, value.utf8.count <= limits.maximumTextBytes,
                  let rule = schema[key] else { throw JournalTransferError.tooLarge }
            switch rule.type {
            case .text: break
            case .integer(let range): guard range.contains(try integer(key)) else { throw JournalTransferError.invalid }
            case .number: _ = try number(key)
            case .date: _ = try date(key)
            case .boolean: _ = try boolean(key)
            case .enumeration(let values): guard values.contains(value) else { throw JournalTransferError.invalid }
            case .strings(let maximum, let allowed):
                let values = try stringList(key)
                guard values.count <= maximum, values.allSatisfy({ $0.utf8.count <= 4_096 }) else { throw JournalTransferError.tooLarge }
                if let allowed, !values.allSatisfy({ allowed.contains($0) }) { throw JournalTransferError.invalid }
            case .uuids:
                let values = try stringList(key)
                guard values.count <= limits.maximumRecords, Set(values).count == values.count else { throw JournalTransferError.invalid }
                for value in values { try Self.requireUUID(value) }
            case .exercises: _ = try portableExercises()
            }
        }
        if kind == .habit {
            let undoKeys = ["undoCompletionDate", "undoPreviousStreak", "undoPreviousBestStreak", "undoPreviousTotalCompletions"]
            let present = undoKeys.filter { fields[$0] != nil }.count
            guard present == 0 || present == undoKeys.count else { throw JournalTransferError.invalid }
            if present == 0, fields["undoPreviousCompletionDate"] != nil { throw JournalTransferError.invalid }
        }
    }

    static func validateAll(_ records: [Self], limits: JournalTransferLimits,
                            budget: JournalTransferBudget? = nil) throws {
        guard records.count <= limits.maximumRecords else { throw JournalTransferError.tooLarge }
        var identifiers: Set<String> = [], photos = 0, payloadBytes = 0
        for record in records {
            try budget?.check()
            try record.validate(limits: limits, budget: budget)
            guard identifiers.insert(record.kind.rawValue + ":" + record.id).inserted else { throw JournalTransferError.invalid }
            let bytes = record.photo?.count ?? 0
            guard bytes <= limits.maximumTotalPhotoBytes - photos else { throw JournalTransferError.tooLarge }
            photos += bytes
            let encodedBytes = try record.payload(limits: limits).count
            guard encodedBytes <= limits.maximumTotalRecordBytes - payloadBytes else { throw JournalTransferError.tooLarge }
            payloadBytes += encodedBytes
        }
        let profiles = Set(records.filter { $0.kind == .profile }.map(\.id))
        var goalIDsByOwner: [String: Set<String>] = [:]
        for goal in records where goal.kind == .goal {
            if let owner = goal.ownerID { goalIDsByOwner[owner, default: []].insert(goal.id) }
        }
        for record in records {
            try budget?.check()
            if let owner = record.ownerID, !profiles.contains(owner) { throw JournalTransferError.invalid }
            if record.kind == .profile {
                let listed = Set(try record.stringList("goalIDs"))
                let actual = goalIDsByOwner[record.id, default: []]
                guard listed == actual else { throw JournalTransferError.invalid }
            }
        }
    }

    static func requireUUID(_ value: String) throws {
        guard let id = UUID(uuidString: value), id.uuidString == value else { throw JournalTransferError.invalid }
    }

    private static func validatePhoto(_ photo: Data, limits: JournalTransferLimits,
                                      budget: JournalTransferBudget?) throws {
        // Compressed byte limits do not bound declared image dimensions. Check
        // metadata bounds before the small background thumbnail decode below.
        // The original bytes are retained; validation never recompresses photos.
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(photo as CFData, options),
              CGImageSourceGetType(source) != nil else { throw JournalTransferError.invalid }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw JournalTransferError.invalid }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw JournalTransferError.invalid }
        guard count <= limits.maximumPhotoFrames else { throw JournalTransferError.tooLarge }
        var totalPixels: Int64 = 0
        for index in 0..<count {
            try budget?.check()
            guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else {
                throw JournalTransferError.invalid
            }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw JournalTransferError.invalid
            }
            let w = width.int64Value, h = height.int64Value
            guard w > 0, h > 0, w <= Int64(limits.maximumPhotoDimension),
                  h <= Int64(limits.maximumPhotoDimension),
                  w <= (limits.maximumTotalPhotoPixels - totalPixels) / h else {
                throw JournalTransferError.tooLarge
            }
            totalPixels += w * h
            // Headers can be readable even when compressed image data is not.
            // Ask ImageIO for a small thumbnail from the actual full image and
            // draw it, after the original byte/frame/pixel bounds are checked.
            // This validates decoding; the original saved bytes remain intact.
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary),
                  thumbnail.width > 0, thumbnail.width <= 64, thumbnail.height > 0, thumbnail.height <= 64,
                  let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                    bitsPerComponent: 8, bytesPerRow: thumbnail.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw JournalTransferError.invalid
            }
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height)))
            guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else { throw JournalTransferError.invalid }
            try budget?.check()
        }
    }

    private enum FieldType {
        case text, integer(ClosedRange<Int>), number, date, boolean, enumeration(Set<String>)
        case strings(Int, Set<String>?), uuids, exercises
    }
    private struct FieldRule { let type: FieldType; var optional = false }

    private static func schema(_ kind: JournalRecordKind) -> [String: FieldRule] {
        let text = FieldRule(type: .text), number = FieldRule(type: .number), date = FieldRule(type: .date)
        let boolean = FieldRule(type: .boolean), counter = FieldRule(type: .integer(0...1_000_000_000))
        let rating = FieldRule(type: .integer(1...10))
        let mood = FieldRule(type: .enumeration(["Great", "Good", "Okay", "Low", "Struggling"]))
        func optional(_ rule: FieldRule) -> FieldRule { FieldRule(type: rule.type, optional: true) }
        switch kind {
        case .item: return ["timestamp": date, "title": text, "note": text, "isPinned": boolean, "isComplete": boolean, "accentName": text]
        case .profile: return ["name": text, "age": FieldRule(type: .integer(0...150)),
            "gender": FieldRule(type: .enumeration(["Male", "Female", "Other"])), "heightCm": number,
            "currentWeightKg": number, "goalWeightKg": optional(number),
            "experienceLevel": FieldRule(type: .enumeration(["Beginner", "Intermediate", "Advanced"])),
            "primaryGoal": FieldRule(type: .enumeration(["Lose Fat", "Build Muscle", "Improve Strength", "Improve Endurance", "General Health & Fitness"])),
            "workoutDaysPerWeek": FieldRule(type: .integer(0...7)),
            "equipmentAccess": FieldRule(type: .enumeration(["Full Gym Access", "Home Gym (Dumbbells + Bench)", "Minimal (Bodyweight + Resistance Bands)", "No Equipment"])),
            "dietaryPreferences": FieldRule(type: .strings(32, ["No Restrictions", "Vegetarian", "Vegan", "Pescatarian", "Keto", "High Protein"])),
            "injuriesOrLimitations": optional(text), "createdAt": date, "updatedAt": date, "goalIDs": FieldRule(type: .uuids)]
        case .bodyMetric: return ["date": date, "weightKg": optional(number), "bodyFatPercentage": optional(number), "chestCm": optional(number), "waistCm": optional(number), "hipsCm": optional(number), "armsCm": optional(number), "thighsCm": optional(number), "notes": optional(text)]
        case .healthSnapshot: return ["date": date, "restingHeartRate": optional(number), "heartRateVariability": optional(number), "sleepHours": optional(number), "activeEnergyBurned": optional(number), "exerciseMinutes": optional(number), "energyLevel": optional(rating), "sorenessLevel": optional(rating), "mood": optional(mood), "notes": optional(text)]
        case .milestone: return ["title": text, "detail": text, "achievedDate": optional(date), "isAchieved": boolean, "category": FieldRule(type: .enumeration(["consistency", "strength", "bodyComposition", "mindset"]))]
        case .progressPhoto: return ["date": date, "weightAtTime": optional(number), "notes": optional(text)]
        case .streak: return ["type": FieldRule(type: .enumeration(["workout", "checkIn", "nutrition"])), "currentStreak": counter, "longestStreak": counter, "lastCheckIn": optional(date)]
        case .meal: return ["date": date, "mealName": text, "calories": optional(number), "protein": optional(number), "carbs": optional(number), "fat": optional(number), "notes": optional(text)]
        case .checkIn: return ["date": date, "energyLevel": rating, "sorenessLevel": rating, "sleepQuality": rating, "stressLevel": rating, "mood": mood, "journalNote": optional(text), "didTrain": boolean]
        case .workout: return ["date": date, "workoutName": text, "exercises": FieldRule(type: .exercises), "perceivedExertion": optional(rating), "notes": optional(text), "durationMinutes": optional(FieldRule(type: .integer(0...1_000_000)))]
        case .journal: return ["date": date, "title": optional(text), "content": text, "mood": optional(mood), "tags": FieldRule(type: .strings(1_000, nil))]
        case .memory: return ["date": date, "type": FieldRule(type: .enumeration(["reflection", "pattern", "insight"])), "content": text]
        case .goal: return ["name": text, "currentValue": number, "targetValue": number, "unit": text, "category": text, "lastAdjustedByCoach": optional(date), "adjustmentNotes": optional(text)]
        case .habit: return ["name": text, "createdAt": date, "isActive": boolean, "currentStreak": counter, "bestStreak": counter, "totalCompletions": counter, "lastCompletedDate": optional(date), "coachSuggested": boolean, "coachNotes": optional(text), "targetFrequencyPerWeek": FieldRule(type: .integer(1...7)), "undoCompletionDate": optional(date), "undoPreviousCompletionDate": optional(date), "undoPreviousStreak": optional(counter), "undoPreviousBestStreak": optional(counter), "undoPreviousTotalCompletions": optional(counter)]
        }
    }
}

nonisolated struct JournalPortableSet: Codable, Sendable {
    var id: UUID
    var reps: Int
    var weight: String?
    var rpe: Int?
}
nonisolated struct JournalPortableExercise: Codable, Sendable {
    var id: UUID
    var name: String
    var sets: [JournalPortableSet]
}

extension JournalRecoveryRecord {
    nonisolated func portableExercises() throws -> [JournalPortableExercise] {
        let data = Data(try text("exercises").utf8)
        try Self.validateJSON(data, maximumBytes: 1_024 * 1_024, depth: 5)
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], objects.count <= 200 else {
            throw JournalTransferError.invalid
        }
        for object in objects {
            guard Set(object.keys) == ["id", "name", "sets"], let sets = object["sets"] as? [[String: Any]], sets.count <= 200 else { throw JournalTransferError.invalid }
            for set in sets {
                guard Set(set.keys).isSubset(of: ["id", "reps", "weight", "rpe"]), Set(["id", "reps"]).isSubset(of: Set(set.keys)) else { throw JournalTransferError.invalid }
            }
        }
        // Decode the same checked object representation. Parsing the original
        // bytes independently could give duplicate keys different precedence.
        let canonical = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        guard canonical.count <= 1_024 * 1_024 else { throw JournalTransferError.tooLarge }
        let exercises: [JournalPortableExercise]
        do { exercises = try JSONDecoder().decode([JournalPortableExercise].self, from: canonical) }
        catch { throw JournalTransferError.invalid }
        guard exercises.count <= 200 else { throw JournalTransferError.tooLarge }
        var exerciseIDs: Set<UUID> = [], setIDs: Set<UUID> = []
        for exercise in exercises {
            guard exercise.sets.count <= 200 else { throw JournalTransferError.tooLarge }
            guard exerciseIDs.insert(exercise.id).inserted, exercise.name.utf8.count <= 4_096 else { throw JournalTransferError.invalid }
            for set in exercise.sets {
                guard setIDs.insert(set.id).inserted, (1...1_000_000).contains(set.reps),
                      set.rpe.map({ (1...10).contains($0) }) ?? true else { throw JournalTransferError.invalid }
                if let weight = set.weight {
                    var temporary = self; temporary.fields = ["value": weight]
                    guard try temporary.number("value") >= 0 else { throw JournalTransferError.invalid }
                }
            }
        }
        return exercises
    }

    @MainActor static func encodeExercises(_ exercises: [LoggedExercise]) throws -> String {
        let values = exercises.map { exercise in
            JournalPortableExercise(id: exercise.id, name: exercise.name, sets: exercise.sets.map {
                JournalPortableSet(id: $0.id, reps: $0.reps, weight: $0.weight.map(bits), rpe: $0.rpe)
            })
        }
        return String(decoding: try JSONEncoder.sortedRecovery.encode(values), as: UTF8.self)
    }
    @MainActor func decodedExercises(_ prepared: [JournalPortableExercise]) throws -> [LoggedExercise] {
        try prepared.map { exercise in
            LoggedExercise(id: exercise.id, name: exercise.name, sets: try exercise.sets.map { set in
                let weight: Double? = try set.weight.map { value in
                    var temporary = self; temporary.fields = ["value": value]; return try temporary.number("value")
                }
                return LoggedSet(id: set.id, reps: set.reps, weight: weight, rpe: set.rpe)
            })
        }
    }
    @MainActor func enumValue<T: RawRepresentable>(_ type: T.Type, _ key: String) throws -> T where T.RawValue == String {
        try Self.requireEnum(type, text(key))
    }
    @MainActor static func requireEnum<T: RawRepresentable>(_ type: T.Type, _ value: String) throws -> T where T.RawValue == String {
        guard let result = T(rawValue: value) else { throw JournalTransferError.invalid }; return result
    }
}
