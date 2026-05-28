import SwiftUI
import SwiftData

struct CoachMemoryInsightsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \CoachMemoryEntry.date, order: .reverse) private var memories: [CoachMemoryEntry]
    
    @State private var newMemoryNote = ""
    @State private var showingAddNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What Your Coach Knows")
                            .font(.largeTitle.bold())
                        
                        Text("The AI coach builds a long-term understanding of you from your data, check-ins, and conversations. You can review and teach it here.")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal)

                    // Summary
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                Text("Current Understanding")
                                    .font(.headline)
                            }
                            
                            Text(viewModel.smartMemorySummary.isEmpty ? viewModel.memorySummary : viewModel.smartMemorySummary)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal)

                    // Recent Memories
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Observations & Reflections")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if memories.isEmpty {
                            GlassCard {
                                Text("No memories yet. As you use the app and talk to the coach, it will start building understanding.")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.horizontal)
                        } else {
                            ForEach(memories.prefix(15)) { memory in
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(memory.type.rawValue.capitalized)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(memoryColor(for: memory.type))
                                            Spacer()
                                            Text(memory.date, style: .date)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(memory.content)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Teach the Coach
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Teach Your Coach")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Something important the coach should know about you?")
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Button {
                                    showingAddNote = true
                                } label: {
                                    Label("Add Note to Coach Memory", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .glassBackground()
            .navigationTitle("Coach Memory")
            .sheet(isPresented: $showingAddNote) {
                AddMemoryNoteView { note in
                    viewModel.saveCoachMemoryEntry(type: .reflection, content: "User added: \(note)")
                    showingAddNote = false
                }
            }
        }
    }
    
    private func memoryColor(for type: MemoryType) -> Color {
        switch type {
        case .reflection: return .blue
        case .pattern: return .purple
        case .insight: return .green
        }
    }
}

struct AddMemoryNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("What should your coach remember?") {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Add to Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSave(note)
                        }
                        dismiss()
                    }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}