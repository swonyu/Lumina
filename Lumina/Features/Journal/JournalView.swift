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
                            Text(L("Use your saved notes as prompts for reflection; they do not establish a health pattern."))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            
            if entries.isEmpty { Text(L("No saved journal entries. Add your first entry.")) }
            ForEach(entries) { entry in
                NavigationLink { JournalRecordEditor(entry: entry) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(LocalizationManager.shared.currentLanguage.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let title = entry.title {
                        Text(title)
                            .font(.headline)
                    }
                    
                    Text(entry.content)
                        .lineLimit(3)
                    
                    if let mood = entry.mood {
                        Text(L("journal.mood_prefix", L(mood.rawValue)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(L("tab.journal"))
        .toolbar {
            Button {
                showingNewEntry = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(L("Add journal entry"))
            .accessibilityIdentifier("lumina.journal.add")
        }
        .sheet(isPresented: $showingNewEntry) {
            NewJournalEntryView()
        }
        .glassBackground()
        .withAppLanguage()
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
                        .frame(minHeight: 150)
                        .accessibilityLabel(L("Journal entry"))
                        .accessibilityIdentifier("lumina.journal.new-content")
                }
                
                Section(L("journal.feeling_section")) {
                    Picker(L("journal.mood_picker"), selection: $mood) {
                        ForEach(Mood.allCases, id: \.self) { m in
                            Text(L(m.rawValue)).tag(m)
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
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("lumina.journal.new-save")
                }
            }
        }
    }
    
    private func saveEntry() -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let entry = JournalEntry(content: content, mood: mood)
        return viewModel.saveRecord(entry)
    }
}
