import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    
    @State private var newEntry = ""
    @State private var showingNewEntry = false

    var body: some View {
        List {
            // Round 33: Coach nudge from memory in the reflective Journal space
            if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                if mem.lowercased().contains("mood") || mem.lowercased().contains("energy") || mem.lowercased().contains("consistent") || mem.lowercased().contains("goal") {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            Text("Coach reflection prompt: Your patterns show themes worth journaling about today.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let title = entry.title {
                        Text(title)
                            .font(.headline)
                    }
                    
                    Text(entry.content)
                        .lineLimit(3)
                    
                    if let mood = entry.mood {
                        Text(L("journal.mood_prefix", mood.rawValue))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(L("tab.journal"))
        .toolbar {
            Button {
                showingNewEntry = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewJournalEntryView()
        }
        .glassBackground()
        .withAppLanguage()
        .drawingGroup()  // Round 5 perf improvement for journal list
    }
}

struct NewJournalEntryView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var content = ""
    @State private var mood: Mood = .good

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $content)
                        .frame(height: 150)
                }
                
                Section(L("journal.feeling_section")) {
                    Picker(L("journal.mood_picker"), selection: $mood) {
                        ForEach(Mood.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                }
            }
            .navigationTitle(L("journal.new_entry_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("general.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("general.save")) {
                        if saveEntry() { dismiss() }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func saveEntry() -> Bool {
        let entry = JournalEntry(content: content, mood: mood)
        return viewModel.saveRecord(entry)
    }
}
