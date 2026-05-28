import Foundation

/// Simple in-memory + persistent coach memory for better long-term emotional intelligence
struct CoachMemory {
    static let shared = CoachMemory()
    
    private var recentReflections: [String] = []
    private var userPatterns: [String] = []
    
    private init() {}
    
    mutating func addReflection(_ text: String) {
        recentReflections.append(text)
        if recentReflections.count > 5 {
            recentReflections.removeFirst()
        }
    }
    
    mutating func recordPattern(_ pattern: String) {
        userPatterns.append(pattern)
        if userPatterns.count > 8 {
            userPatterns.removeFirst()
        }
    }
    
    func getRelevantContext() -> String {
        var context = ""
        
        if !recentReflections.isEmpty {
            context += "Recent reflections from previous weeks:\n"
            context += recentReflections.joined(separator: "\n")
        }
        
        if !userPatterns.isEmpty {
            context += "\nNoticed patterns:\n"
            context += userPatterns.joined(separator: "\n")
        }
        
        return context
    }
}
