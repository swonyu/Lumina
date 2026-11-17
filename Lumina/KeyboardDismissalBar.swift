import SwiftUI

/// One focus binding for the complete new/saved workout screen.
enum WorkoutInputFocus: Hashable {
    case name, notes, workoutExertion, duration
    case exercise(UUID), repetitions(UUID), weight(UUID), exertion(UUID)
}

extension View {
    /// A regular safe-area view keeps numeric-keyboard dismissal reachable
    /// without an accessory toolbar whose initial width may be undefined.
    func keyboardDismissalBar(isFocused: Bool, dismiss: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isFocused {
                HStack {
                    Spacer(minLength: 0)
                    Button(L("Done"), action: dismiss)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("lumina.keyboard.done")
                }
                .padding(.horizontal, 16)
                .background(.bar)
            }
        }
    }
}
