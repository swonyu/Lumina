import SwiftUI
import SwiftData

struct DailyCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LuminaViewModel.self) private var viewModel
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
                Text(L("checkin.how_are_you"))
                    .font(.largeTitle.bold())
                    .padding(.top)
                
                // Round 85/86: Limited-impact awareness on the core daily check-in surface (now uses cheap VM computed)
                if viewModel.hasLimitedCoachHabitImpact {
                    GlassCard {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            Text("Record how you feel. A check-in does not prove that a habit caused a change.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SliderRow(title: L("checkin.energy"), value: $energy, range: 1...10)
                        SliderRow(title: L("checkin.soreness"), value: $soreness, range: 1...10)
                        SliderRow(title: L("checkin.sleep_quality"), value: $sleepQuality, range: 1...10)
                        SliderRow(title: L("checkin.stress"), value: $stress, range: 1...10)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("checkin.mood_question"))
                            .font(.headline)
                        Picker(L("checkin.mood"), selection: $mood) {
                            ForEach(Mood.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("checkin.note_question"))
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Toggle(L("checkin.trained_today"), isOn: $didTrain)
                    .padding()
                    .glassBackground()

                GlassButton(title: L("checkin.save_button"), isProminent: true, action: {
                    saveCheckIn()
                })
                .padding(.horizontal)
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.checkin"))
        .withAppLanguage()
        .alert(L("checkin.saved_alert_title"), isPresented: $showingSuccess) {
            Button(L("general.ok")) { }
        } message: {
            Text(L("checkin.saved_alert_message"))
        }
        .drawingGroup() // Round 14 perf
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
        guard viewModel.saveRecord(checkIn) else { return }
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
