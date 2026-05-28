import SwiftUI

struct HabitTrackerView: View {
    @State private var habits: [(name: String, done: Bool)] = [
        ("Morning sunlight", true),
        ("Protein goal", false),
        ("10k steps", true),
        ("No screens after 10pm", false)
    ]
    @State private var showingNewHabit = false
    @State private var newHabitName = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily Habits")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                
                ForEach(habits.indices, id: \.self) { index in
                    GlassCard {
                        HStack {
                            Text(habits[index].name)
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                habits[index].done.toggle()
                            } label: {
                                Image(systemName: habits[index].done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(habits[index].done ? .green : .white.opacity(0.5))
                                    .font(.title2)
                            }
                        }
                    }
                }
                
                GlassButton(title: "+ New Habit") {
                    showingNewHabit = true
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Habits")
        .alert("New Habit", isPresented: $showingNewHabit) {
            TextField("Habit name", text: $newHabitName)
            Button("Add") {
                if !newHabitName.trimmingCharacters(in: .whitespaces).isEmpty {
                    habits.append((name: newHabitName, done: false))
                    newHabitName = ""
                }
            }
            Button("Cancel", role: .cancel) { newHabitName = "" }
        } message: {
            Text("What habit do you want to track?")
        }
    }
}
