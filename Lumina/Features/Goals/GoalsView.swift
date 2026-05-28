import SwiftUI

struct GoalsView: View {
    @State private var goals: [GoalItem] = [
        GoalItem(name: "Lose 8kg", current: 3.2, target: 8, unit: "kg")
    ]
    @State private var showingAddGoal = false
    @State private var newGoalName = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Goals")
                    .font(.largeTitle.bold())
                
                ForEach(goals) { goal in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(goal.name)
                                .font(.headline)
                            ProgressView(value: goal.progress)
                            Text("\(String(format: "%.1f", goal.current))\(goal.unit) / \(String(format: "%.0f", goal.target))\(goal.unit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                GlassButton(title: "+ Add New Goal") {
                    showingAddGoal = true
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Goals")
        .alert("New Goal", isPresented: $showingAddGoal) {
            TextField("Goal name (e.g. Run 5k)", text: $newGoalName)
            Button("Add") {
                if !newGoalName.trimmingCharacters(in: .whitespaces).isEmpty {
                    goals.append(GoalItem(name: newGoalName, current: 0, target: 10, unit: ""))
                    newGoalName = ""
                }
            }
            Button("Cancel", role: .cancel) { newGoalName = "" }
        }
    }
}

struct GoalItem: Identifiable {
    let id = UUID()
    var name: String
    var current: Double
    var target: Double
    var unit: String
    
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }
}
