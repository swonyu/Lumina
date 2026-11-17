import Foundation
import FoundationModels

/// Uses only the system's already-available on-device model. No model assets,
/// download flow, API key, cloud provider, tools or external requests.
@MainActor
final class FoundationModelCoachGenerator: OnDeviceCoachGenerating {
    // Also bound admission across separately created chat views/services.
    // A timeout cancels generation; only actual termination releases this gate.
    private static var isGenerating = false

    func availability(for locale: Locale) -> CoachModelAvailability {
        let model = SystemLanguageModel.default
        let state = model.availability
        let supportsLocale = state == .available && model.supportsLocale(locale)
        return Self.mapAvailability(state, supportsLocale: supportsLocale)
    }

    static func mapAvailability(_ state: SystemLanguageModel.Availability,
                                supportsLocale: Bool) -> CoachModelAvailability {
        switch state {
        case .available:
            return supportsLocale ? .available : .unavailable(.unsupportedLanguage)
        case .unavailable(.deviceNotEligible): return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(.intelligenceNotEnabled)
        case .unavailable(.modelNotReady): return .unavailable(.modelNotReady)
        case .unavailable: return .unavailable(.unavailable)
        }
    }

    func generate(_ request: CoachModelRequest) async throws -> String {
        try Task.checkCancellation()
        guard !Self.isGenerating else { throw CoachGenerationFailure.inProgress }
        Self.isGenerating = true
        defer { Self.isGenerating = false }
        if case .unavailable(let reason) = availability(for: Locale(identifier: request.localeIdentifier)) {
            throw CoachGenerationFailure.unavailable(reason)
        }
        let model = SystemLanguageModel.default
        let instructions = Instructions(request.instructions)
        let prompt = Prompt(try request.encodedPrompt())
        do {
            // The deployment target is iOS 26.5; token counting is available
            // from 26.4. Reserve space for the response and framework framing.
            let instructionTokens = try await model.tokenCount(for: instructions)
            let promptTokens = try await model.tokenCount(for: prompt)
            let availableInputTokens = model.contextSize
                - CoachModelRequest.maximumResponseTokens - CoachModelRequest.reservedContextTokens
            guard availableInputTokens > 0,
                  instructionTokens <= availableInputTokens,
                  promptTokens <= availableInputTokens - instructionTokens else {
                throw CoachGenerationFailure.contextLimit
            }
            try Task.checkCancellation()
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt,
                options: GenerationOptions(samplingMode: nil, temperature: nil,
                    maximumResponseTokens: CoachModelRequest.maximumResponseTokens))
            try Task.checkCancellation()
            return response.content
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            throw Self.mapFailure(error)
        }
    }

    static func mapFailure(_ error: Error) -> CoachGenerationFailure {
        if let failure = error as? CoachGenerationFailure { return failure }
        if #available(iOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return .contextLimit
                case .rateLimited: return .rateLimited
                case .guardrailViolation, .refusal: return .refused
                case .unsupportedLanguageOrLocale: return .unavailable(.unsupportedLanguage)
                case .timeout: return .timedOut
                default: return .failed
                }
            }
            if let error = error as? SystemLanguageModel.Error {
                switch error {
                case .assetsUnavailable: return .unavailable(.modelNotReady)
                @unknown default: return .failed
                }
            }
            return .failed
        } else {
            return mapLegacyFailure(error)
        }
    }

    // Explicitly bounded to iOS 26 so Xcode 27 does not ship the obsolete
    // error contract on newer systems, or introduce deprecation warnings.
    @available(iOS, introduced: 26.0, obsoleted: 27.0)
    private static func mapLegacyFailure(_ error: Error) -> CoachGenerationFailure {
        guard let error = error as? LanguageModelSession.GenerationError else { return .failed }
        switch error {
        case .assetsUnavailable: return .unavailable(.modelNotReady)
        case .exceededContextWindowSize: return .contextLimit
        case .guardrailViolation, .refusal: return .refused
        case .unsupportedLanguageOrLocale: return .unavailable(.unsupportedLanguage)
        case .rateLimited: return .rateLimited
        default: return .failed
        }
    }
}
