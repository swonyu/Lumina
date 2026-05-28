import SwiftUI
import SwiftData

struct MealLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var mealName = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var showingSuccess = false
    
    @Query(sort: \MealLog.date, order: .reverse) private var recentMeals: [MealLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Log Meal")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    TextField("What did you eat?", text: $mealName)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Calories: \(Int(calories))", value: $calories, in: 0...2000, step: 10)
                    Stepper("Protein: \(Int(protein))g", value: $protein, in: 0...200, step: 5)
                }
                
                GlassButton(title: "Save Meal", isProminent: true) {
                    saveMeal()
                }
                
                if recentMeals.isEmpty {
                    Text("Log your first meal to start tracking nutrition history.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                } else {
                    GlassCard {
                        Text("Recent Meals")
                            .font(.headline)
                        ForEach(recentMeals.prefix(3)) { meal in
                            HStack {
                                Text(meal.mealName)
                                Spacer()
                                if let cals = meal.calories {
                                    Text("\(Int(cals)) cal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Nutrition")
        .alert("Meal logged!", isPresented: $showingSuccess) {
            Button("OK") { }
        }
    }
    
    private func saveMeal() {
        guard !mealName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let log = MealLog(mealName: mealName, calories: calories, protein: protein)
        modelContext.insert(log)
        try? modelContext.save()
        mealName = ""
        calories = 0
        protein = 0
        showingSuccess = true
    }
}
