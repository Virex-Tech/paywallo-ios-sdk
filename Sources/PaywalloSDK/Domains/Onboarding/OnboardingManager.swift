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

    /// Registra a resposta de uma ramificação do onboarding (`key` -> `value`), após trim.
    /// key: letras ASCII, dígitos, `_ . -` (1–64); value: texto livre de 1–64 caracteres (sem controle,
    /// fora `__none__`/`__other__`/`__all__`); fora disso é ignorado com aviso. Ex.: `branch(key: "objetivo", value: "perder peso")`.
    public func branch(key: String, value: String) async throws {
        guard trackEvent != nil else {
            throw OnboardingError(code: OnboardingErrorCode.notInitialized, message: "OnboardingManager not initialized")
        }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            print("[Paywallo:Onboarding] branch ignorado: key \"\(k)\" deve casar [A-Za-z0-9_.-]{1,64}")
            return
        }
        // utf16.count: o limite do servidor é em unidades UTF-16, não em Characters.
        let hasControl = v.unicodeScalars.contains { $0.value <= 0x1F || (0x7F...0x9F).contains($0.value) }
        guard (1...64).contains(v.utf16.count), !hasControl, !["__none__", "__other__", "__all__"].contains(v) else {
            print("[Paywallo:Onboarding] branch ignorado: value inválido (1–64 caracteres, sem controle, não reservado): \"\(v)\"")
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
