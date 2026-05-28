//
//  Item.swift
//  Lumina
//
//  Created by saleh alayed on 10/12/1447 AH.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var title: String
    var note: String
    var isPinned: Bool
    var isComplete: Bool
    var accentName: String

    init(
        timestamp: Date = Date(),
        title: String = "New idea",
        note: String = "Capture a thought, plan, or reminder.",
        isPinned: Bool = false,
        isComplete: Bool = false,
        accentName: String = "blue"
    ) {
        self.timestamp = timestamp
        self.title = title
        self.note = note
        self.isPinned = isPinned
        self.isComplete = isComplete
        self.accentName = accentName
    }
}
