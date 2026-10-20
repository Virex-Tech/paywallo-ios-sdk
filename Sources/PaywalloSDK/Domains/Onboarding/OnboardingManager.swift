import Foundation

public final class OnboardingManager {
    private var trackEvent: ((String, [String: AnyCodable], EventPriority) async -> Void)?
    private var distinctIdProvider: (() -> String)?
    private var finished = false
    private var lastStep: String?
    private var debug = false

    public init() {}

    public func injectDeps(
        trackEvent: @escaping (String, [String: AnyCodable], EventPriority) async -> Void,
        distinctIdProvider: @escaping () -> String,
        debug: Bool = false
    ) {
        self.trackEvent = trackEvent
        self.distinctIdProvider = distinctIdProvider
        self.debug = debug
    }

    public func step(stepName: String, order: Double, variantKey: String? = nil, timeOnPrevS: Double? = nil) async throws {
        guard trackEvent != nil else {
            throw OnboardingError(code: OnboardingErrorCode.notInitialized, message: "OnboardingManager not initialized")
        }
        guard !stepName.isEmpty else {
            throw OnboardingError(code: OnboardingErrorCode.invalidStepName, message: "Step name cannot be empty")
        }
        guard order.isFinite && order >= 0 else {
            throw OnboardingError(code: OnboardingErrorCode.invalidOrder, message: "order deve ser um número finito e não-negativo")
        }

        let distinctId = distinctIdProvider?() ?? ""
        guard !distinctId.isEmpty else { return } // silently skip

        var payload: [String: AnyCodable] = [
            "family": AnyCodable("onboarding"),
            "type": AnyCodable("step"),
            "step_name": AnyCodable(stepName),
            "order": AnyCodable(order),
        ]
        if let vk = variantKey { payload["variant_key"] = AnyCodable(vk) }
        if let t = timeOnPrevS { payload["time_on_prev_s"] = AnyCodable(t) }

        lastStep = stepName
        // Do NOT mark finished

        await trackEvent?("onboarding", payload, .normal)
    }

    public func complete(variantKey: String? = nil) async throws {
        guard trackEvent != nil else {
            throw OnboardingError(code: OnboardingErrorCode.notInitialized, message: "OnboardingManager not initialized")
        }

        let distinctId = distinctIdProvider?() ?? ""
        guard !distinctId.isEmpty else { return }

        var payload: [String: AnyCodable] = [
            "family": AnyCodable("onboarding"),
            "type": AnyCodable("complete"),
        ]
        if let vk = variantKey { payload["variant_key"] = AnyCodable(vk) }

        finished = true
        await trackEvent?("onboarding", payload, .normal)
    }

    /// Registra a resposta de uma ramificação do onboarding (`key` -> `value`), limitada a 64 caracteres após trim.
    public func branch(key: String, value: String) async throws {
        guard trackEvent != nil else {
            throw OnboardingError(code: OnboardingErrorCode.notInitialized, message: "OnboardingManager not initialized")
        }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !v.isEmpty, k.count <= 64, v.count <= 64 else {
            if debug { print("[Paywallo:Onboarding] branch ignorado: key/value vazio ou acima de 64 caracteres") }
            return
        }

        let distinctId = distinctIdProvider?() ?? ""
        guard !distinctId.isEmpty else { return }

        let payload: [String: AnyCodable] = [
            "family": AnyCodable("onboarding"),
            "type": AnyCodable("branch"),
            "key": AnyCodable(k),
            "value": AnyCodable(v),
        ]
        await trackEvent?("onboarding", payload, .normal)
    }

    public var isFinished: Bool { finished }
}
