import SwiftUI

struct ModernHomeView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    private var greetingName: String {
        viewModel.currentUser?.name ?? "there"
    }
    
    private var currentStreak: Int {
        // Simple demo streak based on recent check-ins (in real app would be smarter)
        min(viewModel.recentHealthSnapshots.count + 8, 14)
    }
    
    private var readinessValue: Int {
        viewModel.readinessValue
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {   // Reduced spacing for less work
                    // Greeting - kept light
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Good morning, \(greetingName)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Day \(currentStreak) • You're building something real.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Readiness Rings - reduced size slightly for perf
                    HStack(spacing: 12) {
                        GlassProgressRing(progress: Double(readinessValue) / 100.0, size: 82, lineWidth: 7, color: .green, title: "Readiness", valueText: "\(readinessValue)")
                        GlassProgressRing(progress: Double(viewModel.recoveryValue) / 100.0, size: 82, lineWidth: 7, color: .blue, title: "Recovery", valueText: "\(viewModel.recoveryValue)")
                        GlassProgressRing(progress: Double(viewModel.nutritionValue) / 100.0, size: 82, lineWidth: 7, color: .orange, title: "Nutrition", valueText: "\(viewModel.nutritionValue)")
                    }
                    .padding(.horizontal, 20)
                    
                    // AI Coach Insight - using ultra light card
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                                Text("Coach Insight")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            
                            Text(viewModel.coachInsightText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                            
                            NavigationLink(destination: RealAIChatView()) {
                                Text("Talk to your coach")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Today's Focus - lighter card
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Today’s Focus")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(viewModel.todaysFocusDuration)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Text("\(viewModel.todaysFocusWorkout) • \(focusExercises(for: viewModel.currentUser?.primaryGoal))")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                            
                            NavigationLink(destination: WorkoutLogView()) {
                                Text("Start Workout")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Quick Actions - simplified
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Actions")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            NavigationLink(destination: DailyCheckInView()) {
                                Label("Daily Check-in", systemImage: "heart.text.square")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(destination: RealAIChatView()) {
                                Label("Talk to Coach", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Nutrition - very light
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nutrition Today")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Text("Protein on track • \(viewModel.nutritionValue)% of target")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 50)
                .drawingGroup()   // ← Major performance win for the entire home content
            }
            .background(
                LinearGradient(
                    colors: [.black, Color.black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }
    
    private func focusExercises(for goal: PrimaryGoal?) -> String {
        switch goal {
        case .buildMuscle: return "Bench, OHP, Dips"
        case .loseFat: return "Full body circuit + cardio"
        case .improveStrength: return "Heavy compounds (Squat, Deadlift, Press)"
        case .improveEndurance: return "Metcon + running intervals"
        default: return "Balanced strength + conditioning"
        }
    }
}
