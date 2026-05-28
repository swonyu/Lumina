import SwiftUI
import SwiftData

struct DailyCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var energy = 5
    @State private var soreness = 3
    @State private var sleepQuality = 6
    @State private var stress = 4
    @State private var mood: Mood = .good
    @State private var note = ""
    @State private var didTrain = false
    
    @State private var showingSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text("How are you today?")
                    .font(.largeTitle.bold())
                    .padding(.top)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SliderRow(title: "Energy", value: $energy, range: 1...10)
                        SliderRow(title: "Soreness", value: $soreness, range: 1...10)
                        SliderRow(title: "Sleep Quality", value: $sleepQuality, range: 1...10)
                        SliderRow(title: "Stress", value: $stress, range: 1...10)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading) {
                        Text("How's your mood?")
                            .font(.headline)
                        Picker("Mood", selection: $mood) {
                            ForEach(Mood.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading) {
                        Text("Anything on your mind?")
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Toggle("I trained today", isOn: $didTrain)
                    .padding()
                    .glassBackground()

                GlassButton(title: "Save Check-in", isProminent: true) {
                    saveCheckIn()
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Daily Check-in")
        .alert("Check-in saved", isPresented: $showingSuccess) {
            Button("OK") { }
        } message: {
            Text("Thank you for being honest. Your coach is listening.")
        }
    }
    
    private func saveCheckIn() {
        let checkIn = DailyCheckIn(
            energyLevel: energy,
            sorenessLevel: soreness,
            sleepQuality: sleepQuality,
            stressLevel: stress,
            mood: mood,
            journalNote: note.isEmpty ? nil : note,
            didTrain: didTrain
        )
        modelContext.insert(checkIn)
        try? modelContext.save()
        showingSuccess = true
        
        // Reset for next check-in
        energy = 5
        soreness = 3
        sleepQuality = 6
        stress = 4
        mood = .good
        note = ""
        didTrain = false
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.headline)
            }
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
        }
    }
}
