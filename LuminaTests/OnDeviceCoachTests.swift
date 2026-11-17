import Foundation
import FoundationModels
import Testing
@testable import Lumina

@MainActor
struct OnDeviceCoachTests {
    @Test func frameworkAvailabilityMappingRetainsEveryReason() {
        #expect(FoundationModelCoachGenerator.mapAvailability(.available, supportsLocale: true) == .available)
        #expect(FoundationModelCoachGenerator.mapAvailability(.available, supportsLocale: false)
            == .unavailable(.unsupportedLanguage))
        #expect(FoundationModelCoachGenerator.mapAvailability(.unavailable(.deviceNotEligible), supportsLocale: true)
            == .unavailable(.deviceNotEligible))
        #expect(FoundationModelCoachGenerator.mapAvailability(.unavailable(.appleIntelligenceNotEnabled), supportsLocale: true)
            == .unavailable(.intelligenceNotEnabled))
        #expect(FoundationModelCoachGenerator.mapAvailability(.unavailable(.modelNotReady), supportsLocale: true)
            == .unavailable(.modelNotReady))
    }

    @Test func unavailableModelsNeverGenerateAndKeepUsefulEnglishAndArabicRules() async throws {
        for reason in [CoachUnavailableReason.deviceNotEligible, .intelligenceNotEnabled,
                       .modelNotReady, .unsupportedLanguage, .unavailable] {
            let generator = GeneratorDouble()
            generator.state = .unavailable(reason)
            let coach = OnDeviceCoach(generator: generator)
            let response = try await coach.reply(to: "How am I doing?", context: context(), locale: english)
            #expect(response.text == "Your logs can help you reflect on your goals. Offline coaching cannot determine physical progress or a habit's effects.")
            #expect(response.source == .offlineRules(.unavailable(reason)))
            let arabic = try await coach.reply(to: "كيف أتقدم؟", context: context(), locale: Locale(identifier: "ar"))
            #expect(arabic.text.contains("الإرشاد دون اتصال"))
            #expect(arabic.source == .offlineRules(.unavailable(reason)))
            #expect(generator.requests.isEmpty)
        }
    }

    @Test func successfulReplyHasTrueProvenanceAndExcludesUnverifiedHistory() async throws {
        let generator = GeneratorDouble()
        generator.answer = "  Fixture on-device answer.  "
        let meal = MealLog(mealName: "Saved fixture", protein: 1e300)
        let recorded = context(meals: [meal], insights: ["UNVERIFIED_PHOTO_HABIT_EFFECT"])
        let response = try await OnDeviceCoach(generator: generator).reply(to: " Hello ", context: recorded,
            history: [CoachConversationTurn(role: .user, text: "Earlier question")], locale: english)
        #expect(response == CoachReply(text: "Fixture on-device answer.", source: .appleIntelligence))
        let request = try #require(generator.requests.first)
        #expect(request.question == "Hello")
        #expect(request.recordSummary.contains("Total recorded protein: 1e+300 g"))
        #expect(!request.recordSummary.contains("UNVERIFIED_PHOTO_HABIT_EFFECT"))
        #expect(request.recentConversation.first?.text == "Earlier question")
        #expect(request.instructions.contains("do not calculate new totals"))
        #expect(meal.protein == 1e300)
        #expect(generator.requests.count == 1)
    }

    @Test func boundedPromptPreservesWholeNumericLinesAndDisclosesEveryExcerpt() throws {
        let numericLine = "Total recorded protein: 1e+300 g."
        let preceding = String(repeating: "a", count: CoachModelRequest.maximumContextBytes - 10)
        let history = (0..<12).map { index in
            CoachConversationTurn(role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "\(index):" + String(repeating: "🙂مرحبا", count: 200))
        }
        let request = CoachModelRequest(question: "Keep the whole question?",
            recordSummary: preceding + "\n" + numericLine,
            history: history, locale: english)
        #expect(request.question == "Keep the whole question?")
        #expect(request.recordSummary == preceding)
        #expect(!request.recordSummary.contains("Total recorded protein:"))
        #expect(request.recordSummaryWasTruncated)
        #expect(request.recordSummary.utf8.count <= CoachModelRequest.maximumContextBytes)
        #expect(request.recentConversation.count == 4)
        #expect(request.recentConversation.first?.text.hasPrefix("8:") == true)
        #expect(request.historyWasTrimmed)
        for turn in request.recentConversation {
            #expect(turn.text.utf8.count <= CoachModelRequest.maximumTurnBytes)
            #expect(turn.wasTruncated)
            #expect(!turn.text.contains("\u{FFFD}"))
        }
        let data = try #require(try request.encodedPrompt().data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["question"] as? String == request.question)
        #expect(payload["savedRecordSummaryWasTruncated"] as? Bool == true)
        #expect(payload["conversationWasTrimmed"] as? Bool == true)
        let complete = CoachModelRequest(question: "Hi", recordSummary: numericLine,
            history: [], locale: english)
        #expect(complete.recordSummary == numericLine && !complete.recordSummaryWasTruncated)
        #expect(!complete.historyWasTrimmed)
    }

    @Test func overlongQuestionIsNotSilentlyTruncatedOrSentToTheModel() async throws {
        let generator = GeneratorDouble()
        let question = String(repeating: "🙂", count: CoachModelRequest.maximumQuestionBytes / 4 + 1)
        let response = try await OnDeviceCoach(generator: generator).reply(to: question,
            context: context(), locale: english)
        #expect(response.source == .offlineRules(.messageTooLong))
        #expect(!response.text.isEmpty)
        #expect(generator.requests.isEmpty)
        #expect(question.utf8.count > CoachModelRequest.maximumQuestionBytes)
    }

    @Test func refusalReturnsANoticeWithoutRetryingTrainingRules() async throws {
        let generator = GeneratorDouble()
        generator.failure = .refused
        let response = try await OnDeviceCoach(generator: generator).reply(to: "workout and gym",
            context: context(), locale: english)
        #expect(response.source == .appNotice)
        #expect(response.text.contains("could not help with that request"))
        #expect(!response.text.contains("aim for clean reps"))
        #expect(generator.requests.count == 1)
    }

    @Test func operationalErrorsAndEmptyAnswersUseTruthfulLocalFallbacks() async throws {
        let cases: [(CoachGenerationFailure, CoachFallbackReason)] = [
            (.unavailable(.modelNotReady), .unavailable(.modelNotReady)),
            (.unavailable(.unsupportedLanguage), .unavailable(.unsupportedLanguage)),
            (.contextLimit, .contextLimit), (.rateLimited, .rateLimited),
            (.inProgress, .inProgress), (.timedOut, .timedOut), (.failed, .failed)
        ]
        for (failure, reason) in cases {
            let generator = GeneratorDouble()
            generator.failure = failure
            let response = try await OnDeviceCoach(generator: generator).reply(to: "How am I doing?",
                context: context(), locale: english)
            #expect(response.source == .offlineRules(reason))
            #expect(response.text.contains("Offline coaching cannot determine physical progress"))
            #expect(generator.requests.count == 1)
        }
        let empty = GeneratorDouble()
        empty.answer = " \n "
        let response = try await OnDeviceCoach(generator: empty).reply(to: "Hello", context: context(), locale: english)
        #expect(response.source == .offlineRules(.failed))
        #expect(!response.text.isEmpty)
    }

    @Test func cancellationBeforeAdmissionDoesNotGenerateOrInventAReply() async throws {
        let generator = GeneratorDouble()
        let coach = OnDeviceCoach(generator: generator)
        let task = Task { try await coach.reply(to: "Hello", context: context(), locale: english) }
        task.cancel()
        await expectCancellation(task)
        #expect(generator.requests.isEmpty)
    }

    @Test func cancelledSlowRequestHoldsAdmissionUntilItActuallyTerminates() async throws {
        let generator = GeneratorDouble()
        generator.shouldSuspend = true
        defer { generator.completeAll(with: "Late cleanup answer") }
        let coach = OnDeviceCoach(generator: generator, timeout: .seconds(2))
        let task = Task { try await coach.reply(to: "First", context: context(), locale: english) }
        try await generator.waitUntilSuspended()
        task.cancel()
        await expectCancellation(task)

        let retry = try await coach.reply(to: "Second", context: context(), locale: english)
        #expect(retry.source == .offlineRules(.inProgress))
        #expect(generator.requests.count == 1)
        generator.shouldSuspend = false
        generator.answer = "Only the new answer"
        generator.completeAll(with: "Obsolete cancelled answer")
        let fresh = try await nextModelReply(coach)
        #expect(fresh == CoachReply(text: "Only the new answer", source: .appleIntelligence))
        #expect(generator.requests.count == 2)
        #expect(generator.pending.isEmpty)
    }

    @Test func timeoutReturnsPromptlyWithoutOverlappingOrAcceptingLateGeneration() async throws {
        let generator = GeneratorDouble()
        generator.shouldSuspend = true
        defer { generator.completeAll(with: "Late cleanup answer") }
        let coach = OnDeviceCoach(generator: generator, timeout: .milliseconds(20))
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await coach.reply(to: "First", context: context(), locale: english)
        #expect(start.duration(to: clock.now) < .seconds(1))
        #expect(response.source == .offlineRules(.timedOut))
        #expect(generator.pending.count == 1)
        for _ in 0..<3 {
            let retry = try await coach.reply(to: "Retry", context: context(), locale: english)
            #expect(retry.source == .offlineRules(.inProgress))
        }
        #expect(generator.requests.count == 1)
        generator.shouldSuspend = false
        generator.answer = "Fresh answer after termination"
        generator.completeAll(with: "Late answer that must be discarded")
        let fresh = try await nextModelReply(coach)
        #expect(fresh.text == "Fresh answer after termination")
        #expect(fresh.source == .appleIntelligence)
        #expect(response.source == .offlineRules(.timedOut))
        #expect(generator.requests.count == 2)
    }

    private let english = Locale(identifier: "en")

    private func context(meals: [MealLog] = [], insights: [String] = []) -> CoachContext {
        CoachContext(profile: nil, recentHealth: [], recentCheckIns: [], recentWorkouts: [],
            recentMeals: meals, activeHabits: [], recentInsights: insights, currentStreak: 0)
    }

    private func expectCancellation(_ task: Task<CoachReply, Error>) async {
        do {
            _ = try await task.value
            Issue.record("A cancelled request must throw CancellationError, not return a reply")
        } catch is CancellationError { }
        catch { Issue.record("Unexpected cancellation error: \(error)") }
    }

    private func nextModelReply(_ coach: OnDeviceCoach) async throws -> CoachReply {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            let response = try await coach.reply(to: "Fresh request", context: context(), locale: english)
            if response.source != .offlineRules(.inProgress) { return response }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw FixtureError.generationDidNotTerminate
    }

    private enum FixtureError: Error { case generationDidNotStart, generationDidNotTerminate }

    @MainActor
    private final class GeneratorDouble: OnDeviceCoachGenerating {
        var state: CoachModelAvailability = .available
        var answer = "Fixture answer"
        var failure: CoachGenerationFailure?
        var shouldSuspend = false
        var requests: [CoachModelRequest] = []
        var pending: [CheckedContinuation<String, Error>] = []

        func availability(for locale: Locale) -> CoachModelAvailability { state }

        func generate(_ request: CoachModelRequest) async throws -> String {
            requests.append(request)
            if shouldSuspend {
                // Deliberately ignores cancellation to test the outer deadline
                // and admission contract without invoking any real model.
                return try await withCheckedThrowingContinuation { pending.append($0) }
            }
            if let failure { throw failure }
            return answer
        }

        func waitUntilSuspended() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(1))
            while pending.isEmpty, clock.now < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            guard !pending.isEmpty else { throw FixtureError.generationDidNotStart }
        }

        func completeAll(with answer: String) {
            let waiting = pending
            pending.removeAll()
            for continuation in waiting { continuation.resume(returning: answer) }
        }
    }
}
