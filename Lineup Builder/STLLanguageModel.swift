import Foundation
import FoundationModels

// MARK: - STLLanguageModel
//
// Single decision point for which FoundationModels backend the app's LLM
// features run on: PrivateCloudCompute (32k context, configurable reasoning)
// on iOS 27 when the device is eligible, on-device SystemLanguageModel
// everywhere else. Every LanguageModelSession the app builds should come
// from here so a new OS release only changes behavior in one place.
//
// `nonisolated` because callers span both the main actor
// (AutoFillNLConstraintService) and a detached background task
// (GameLogInsightsService.runInference), and none of this reads mutable
// state — it's pure decision logic over framework availability.
//
// iOS 26 behavior is unchanged by design: every PCC code path is gated
// behind `if #available(iOS 27, *)`, and the on-device fallback below is the
// same construction the two call sites used directly before this file
// existed.
nonisolated enum STLLanguageModel {

    enum Backend {
        case pcc
        case onDevice
    }

    /// Maps to the SDK's `ContextOptions.ReasoningLevel`. Only meaningful on
    /// PCC — the on-device model doesn't declare the `.reasoning` capability.
    enum Reasoning {
        case light
        case deep
    }

    /// A constructed session plus which backend it's on, so callers can
    /// thread reasoning depth and capability checks through to their
    /// `respond(...)` call sites.
    struct Session {
        let session: LanguageModelSession
        let backend: Backend
    }

    /// PrivateCloudCompute requires the MANAGED entitlement
    /// `com.apple.developer.private-cloud-compute`, which Apple grants only after
    /// an eligibility request is approved. Without it, FoundationModels does NOT
    /// degrade gracefully: establishing a PCC-backed session traps with a
    /// non-catchable `Fatal error: Missing entitlement` (ErrorConversion.swift:140),
    /// which crash-loops the app on launch on any device that reaches the model
    /// path. `pccModel.isAvailable` does NOT reflect the entitlement, so it can't
    /// gate this — this flag is the gate.
    ///
    /// Keep this FALSE until (1) the entitlement is granted and (2) it's added to
    /// the app's .entitlements, then flip to true. When false, `pccModel` is never
    /// even constructed (the checks below short-circuit before it), so no PCC code
    /// runs and the app uses the on-device model exactly as it did pre-PCC.
    /// Request form: https://developer.apple.com/contact/request/private-cloud-compute/
    private static let pccEnabled = false

    @available(iOS 27, *)
    private static let pccModel = PrivateCloudComputeLanguageModel()

    /// True when any backend can serve a request: PCC on 27 when the device
    /// is eligible, else the on-device model. Replaces the direct
    /// `SystemLanguageModel.default.availability` reads that used to live in
    /// AutoFillNLConstraintService and GameLogInsightsService.
    static var isAvailable: Bool {
        if #available(iOS 27, *), pccEnabled, pccModel.isAvailable {
            return true
        }
        return onDeviceAvailable
    }

    /// Builds a session on the best available backend, or nil if neither is
    /// usable. Preserves the existing no-model behavior: callers still treat
    /// a nil result as "Apple Intelligence isn't available here."
    static func makeSession(instructions: String) -> Session? {
        if #available(iOS 27, *), pccEnabled, pccModel.isAvailable {
            return Session(
                session: LanguageModelSession(
                    model: pccModel,
                    dynamicInstructions: Instructions(instructions)
                ),
                backend: .pcc
            )
        }
        guard onDeviceAvailable else { return nil }
        return Session(
            session: LanguageModelSession(instructions: instructions),
            backend: .onDevice
        )
    }

    /// A session pinned to the on-device model, ignoring PCC entirely. Used
    /// to retry a single call after a PCC-specific failure (CONFIRM #6), and
    /// to keep Auto-Fill's constrained-decoding path on-device for a call
    /// where PCC doesn't declare `.guidedGeneration` (CONFIRM #3) — never a
    /// silent downgrade to unconstrained prose matching.
    static func onDeviceSession(instructions: String) -> Session? {
        guard onDeviceAvailable else { return nil }
        return Session(
            session: LanguageModelSession(instructions: instructions),
            backend: .onDevice
        )
    }

    private static var onDeviceAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        @unknown default: return false
        }
    }

    /// Per-call reasoning depth for the PCC path. On-device call sites should
    /// keep using the plain `respond(...)` overloads with no contextOptions
    /// rather than calling this.
    @available(iOS 27, *)
    static func contextOptions(for reasoning: Reasoning) -> ContextOptions {
        switch reasoning {
        case .light: return ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .light)
        case .deep: return ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .deep)
        }
    }

    /// Whether the PCC backend currently declares constrained-decoding
    /// support. Auto-Fill's schema path checks this before trusting PCC with
    /// it — see CONFIRM #3 in the handoff doc.
    @available(iOS 27, *)
    static var pccSupportsGuidedGeneration: Bool {
        pccModel.capabilities.contains(.guidedGeneration)
    }

    /// True when `error` is a PCC-specific failure (network, quota, service)
    /// rather than a genuine generation error — the signal to retry once
    /// on-device instead of surfacing a hard failure to the coach.
    @available(iOS 27, *)
    static func isPCCFailure(_ error: Error) -> Bool {
        error is PrivateCloudComputeLanguageModel.Error
    }

    /// Records `usage` to TelemetryDeck as the `ai.model.usage` signal. Call
    /// once per `respond(...)` site, wrapped in `if #available(iOS 27, *)` —
    /// `LanguageModelSession.Usage` itself is an iOS 27 addition, even for an
    /// on-device-backed response.
    @available(iOS 27, *)
    static func logUsage(_ usage: LanguageModelSession.Usage, backend: Backend, feature: String) {
        Analytics.signal("ai.model.usage", parameters: [
            "backend": backend == .pcc ? "pcc" : "on_device",
            "feature": feature,
            "inputTokens": "\(usage.input.totalTokenCount)",
            "cachedTokens": "\(usage.input.cachedTokenCount)",
            "outputTokens": "\(usage.output.totalTokenCount)",
            "reasoningTokens": "\(usage.output.reasoningTokenCount)"
        ])
    }
}
