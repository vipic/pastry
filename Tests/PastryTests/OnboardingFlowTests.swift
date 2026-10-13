import AppKit
import XCTest
@testable import Pastry

final class OnboardingFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.pastry.onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallNeedsOnboarding() {
        XCTAssertTrue(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testCompletingCurrentVersionStopsAutomaticPresentation() {
        OnboardingPreferences.markCompleted(defaults: defaults)

        XCTAssertFalse(OnboardingPreferences.needsPresentation(defaults: defaults))
        XCTAssertEqual(
            defaults.integer(forKey: UserDefaultsKeys.onboardingCompletedVersion),
            OnboardingPreferences.currentVersion
        )
    }

    func testOlderCompletedVersionPresentsNewOnboarding() {
        defaults.set(
            OnboardingPreferences.currentVersion - 1,
            forKey: UserDefaultsKeys.onboardingCompletedVersion
        )

        XCTAssertTrue(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testLegacyDevelopmentOverrideDoesNotForcePresentation() {
        OnboardingPreferences.markCompleted(defaults: defaults)
        defaults.set(true, forKey: "development_show_onboarding")

        XCTAssertFalse(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testStepsHaveStableForwardAndBackwardOrder() {
        XCTAssertEqual(OnboardingStep.welcome.next, .shortcut)
        XCTAssertEqual(OnboardingStep.shortcut.next, .copy)
        XCTAssertEqual(OnboardingStep.copy.next, .permission)
        XCTAssertNil(OnboardingStep.permission.next)

        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.shortcut.previous, .welcome)
        XCTAssertEqual(OnboardingStep.copy.previous, .shortcut)
        XCTAssertEqual(OnboardingStep.permission.previous, .copy)
    }

    func testIncompleteCopyStepPromptsInsteadOfAdvancing() {
        XCTAssertTrue(OnboardingStep.copy.shouldPromptForCopy(copyComplete: false))
        XCTAssertFalse(OnboardingStep.copy.shouldPromptForCopy(copyComplete: true))
        XCTAssertFalse(OnboardingStep.shortcut.shouldPromptForCopy(copyComplete: false))
    }

    func testCopyDetectionIdentifiesProvidedSampleText() {
        let baseline = UUID()
        var detection = OnboardingCopyDetection(baselineItemIDs: [baseline])
        let sampleText = "这是我的第一条 Pastry 记录"

        XCTAssertFalse(
            detection.observe(
                items: [.init(id: baseline, content: "existing")],
                sampleText: sampleText
            )
        )
        XCTAssertTrue(
            detection.observe(
                items: [
                    .init(id: UUID(), content: sampleText),
                    .init(id: baseline, content: "existing")
                ],
                sampleText: sampleText
            )
        )
        XCTAssertTrue(detection.isComplete)
        XCTAssertEqual(detection.outcome, .sampleText)
    }

    func testCopyDetectionMarksDifferentContentAsExternal() {
        var detection = OnboardingCopyDetection(baselineItemIDs: [])

        XCTAssertTrue(
            detection.observe(
                items: [.init(id: UUID(), content: "copied elsewhere")],
                sampleText: "provided sample"
            )
        )
        XCTAssertEqual(detection.outcome, .otherContent)
    }

    func testCopyDetectionKeepsCompletionOutcomeAfterLaterObservations() {
        var detection = OnboardingCopyDetection(baselineItemIDs: [])
        let sampleText = "provided sample"

        XCTAssertTrue(
            detection.observe(
                items: [.init(id: UUID(), content: "copied elsewhere")],
                sampleText: sampleText
            )
        )
        XCTAssertTrue(
            detection.observe(
                items: [.init(id: UUID(), content: sampleText)],
                sampleText: sampleText
            )
        )
        XCTAssertEqual(detection.outcome, .otherContent)
    }

    @MainActor
    func testOverlayHandoffWaitsForApplicationDeactivationBeforeOpening() {
        let notificationCenter = NotificationCenter()
        let handoff = OnboardingOverlayHandoff()
        var isApplicationActive = true
        var openCount = 0

        handoff.restorePolicyAndOpen(
            savedPolicy: .accessory,
            notificationCenter: notificationCenter,
            isApplicationActive: { isApplicationActive },
            restorePolicy: {},
            openOverlay: { openCount += 1 }
        )

        XCTAssertEqual(openCount, 0)

        isApplicationActive = false
        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)

        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testOverlayHandoffOpensImmediatelyWhenApplicationIsAlreadyInactive() {
        let handoff = OnboardingOverlayHandoff()
        var didRestorePolicy = false
        var openCount = 0

        handoff.restorePolicyAndOpen(
            savedPolicy: .accessory,
            notificationCenter: NotificationCenter(),
            isApplicationActive: { false },
            restorePolicy: { didRestorePolicy = true },
            openOverlay: { openCount += 1 }
        )

        XCTAssertTrue(didRestorePolicy)
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testOverlayHandoffDoesNotWaitWhenRestoringRegularPolicy() {
        let handoff = OnboardingOverlayHandoff()
        var openCount = 0

        handoff.restorePolicyAndOpen(
            savedPolicy: .regular,
            notificationCenter: NotificationCenter(),
            isApplicationActive: { true },
            restorePolicy: {},
            openOverlay: { openCount += 1 }
        )

        XCTAssertEqual(openCount, 1)
    }

}
