import WidgetKit
import SwiftUI

// Round 106: Real-data Home Screen Widget via App Group
//
// To make this widget appear on the Home Screen with live data:
// 1. In Xcode: File → New → Target → Widget Extension (name it LuminaWidget, embed in the Lumina app target).
// 2. Add the same "group.SA.Lumina" App Group to BOTH the main app and the new Widget Extension target (Signing & Capabilities).
// 3. Drag LuminaWidget.swift into the new extension target (or move the Widgets/ folder).
// 4. Build & run the main app once (to populate the shared defaults via syncWidgetData).
// 5. Add the "Lumina Coach" widget to your Home Screen.
//
// After setup, the widget will show real rings + the latest Coach's Daily Briefing / insight,
// refreshed automatically when you open the app or after major actions (check-ins, etc.).

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> LuminaEntry {
        LuminaEntry(date: Date(), rings: (85, 74, 69), coachInsight: "Your coach is tracking real patterns. Open Lumina to refresh the widget.")
    }

    func getSnapshot(in context: Context, completion: @escaping (LuminaEntry) -> ()) {
        // Show realistic demo values; once the Widget Extension target + App Group are added in Xcode, real data flows automatically
        let entry = LuminaEntry(date: Date(), rings: (85, 74, 69), coachInsight: "Consistency compounds. Open Lumina for the latest personalized briefing.")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LuminaEntry>) -> ()) {
        let currentDate = Date()
        let shared = UserDefaults(suiteName: "group.SA.Lumina")

        // Round 106: Read live data pushed from the main Lumina app via App Group
        let readiness = shared?.integer(forKey: "widget.readiness") ?? 82
        let recovery = shared?.integer(forKey: "widget.recovery") ?? 71
        let nutrition = shared?.integer(forKey: "widget.nutrition") ?? 65

        let coachInsight = shared?.string(forKey: "widget.coachInsight")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Consistency compounds. One focused session today aligns with the patterns you've been building."

        let entry = LuminaEntry(
            date: currentDate,
            rings: (readiness: readiness, recovery: recovery, nutrition: nutrition),
            coachInsight: coachInsight.isEmpty ? "Your coach is thinking about your patterns..." : coachInsight
        )

        // Refresh more frequently when we have real data (user can still force by opening the app)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 45, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct LuminaEntry: TimelineEntry {
    let date: Date
    let rings: (readiness: Int, recovery: Int, nutrition: Int)
    let coachInsight: String
}

struct LuminaWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                RingView(value: Double(entry.rings.readiness), color: .green, label: "R")
                RingView(value: Double(entry.rings.recovery), color: .blue, label: "Rec")
                RingView(value: Double(entry.rings.nutrition), color: .orange, label: "Nut")
            }
            
            Text(entry.coachInsight)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // Subtle brand footer (helps when widget is small)
            Text("LUMINA")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 1)
        }
        .padding(10)
        .containerBackground(.black, for: .widget)
    }
}

struct RingView: View {
    let value: Double
    let color: Color
    let label: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }
}

struct LuminaWidget: Widget {
    let kind: String = "LuminaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LuminaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Lumina Coach")
        .description("Your daily rings and coach insight at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}