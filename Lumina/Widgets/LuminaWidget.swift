import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> LuminaEntry { LuminaEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (LuminaEntry) -> Void) {
        completion(LuminaEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LuminaEntry>) -> Void) {
        completion(Timeline(entries: [LuminaEntry(date: Date())], policy: .never))
    }
}
struct LuminaEntry: TimelineEntry { let date: Date }
struct LuminaWidget: Widget {
    let kind = "LuminaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            VStack(alignment: .leading) {
                Text("Lumina").font(.headline)
                Text("Open your journal to review saved records.").font(.caption)
            }
            .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Lumina journal")
        .description("A shortcut to your offline journal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
