import SwiftUI

struct GlassMetricCard: View {
    let title: String
    let value: String
    let change: String?
    let icon: String
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                if let change = change {
                    Text(change)
                        .font(.caption.bold())
                        .foregroundStyle(change.contains("+") || change.contains("↑") ? .green : .red)
                }
            }
        }
    }
}
