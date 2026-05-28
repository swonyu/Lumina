import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    
    @State private var newEntry = ""
    @State private var showingNewEntry = false

    var body: some View {
        List {
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
                        Text("Mood: \(mood.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Journal")
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
    }
}

struct NewJournalEntryView: View {
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
                
                Section("How are you feeling?") {
                    Picker("Mood", selection: $mood) {
                        ForEach(Mood.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                }
            }
            .navigationTitle("New Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func saveEntry() {
        let entry = JournalEntry(content: content, mood: mood)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}
