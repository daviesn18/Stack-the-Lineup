import XCTest
@testable import Lineup_Builder

// MARK: - Account Support Tests (Merge 0)
//
// The pure parts of optional sign-in: the nonce Apple and Google sign, how a
// coach's sign-in methods are named in Settings, the wording of auth errors,
// and the coach-type parameters merged into every analytics signal.

final class AccountSupportTests: XCTestCase {

    // MARK: - Nonce

    func testNonceHashMatchesKnownSHA256() {
        // echo -n "abc" | shasum -a 256
        XCTAssertEqual(SignInNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNonceIsRandomAndTheRequestedLength() {
        let a = SignInNonce.random(), b = SignInNonce.random()
        XCTAssertEqual(a.count, 32)
        XCTAssertEqual(SignInNonce.random(length: 12).count, 12)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Sign-in methods

    func testMethodsComeFromProvidersInAFixedOrder() {
        XCTAssertEqual(SignInMethod.from(providers: ["google", "email"], primary: "email"), [.google, .email])
        XCTAssertEqual(SignInMethod.from(providers: ["Email", "apple"], primary: nil), [.apple, .email])
        // Unknown providers are dropped; an empty list falls back to the primary one.
        XCTAssertEqual(SignInMethod.from(providers: ["github"], primary: "apple"), [])
        XCTAssertEqual(SignInMethod.from(providers: [], primary: "apple"), [.apple])
    }

    func testMethodsReadAsASentence() {
        XCTAssertEqual(SignInMethod.describe([.apple]), "Apple")
        XCTAssertEqual(SignInMethod.describe([.google, .email]), "Google and Email")
        XCTAssertEqual(SignInMethod.describe([.apple, .google, .email]), "Apple, Google and Email")
        XCTAssertEqual(SignInMethod.describe([]), "Email")
    }

    // MARK: - Account label

    func testAppleRelayAddressGivesWayToTheName() {
        let relay = "vyv9yrdvrn@privaterelay.appleid.com"
        XCTAssertTrue(AccountLabel.isAppleRelay(relay))
        XCTAssertEqual(AccountLabel.title(email: relay, name: "Pat Coach"), "Pat Coach")
        XCTAssertEqual(AccountLabel.title(email: relay, name: nil), "Apple Account")
        XCTAssertEqual(AccountLabel.subtitle(methods: [.apple], email: relay), "Signed in with Apple · email hidden")
    }

    func testARealEmailIsShownAsIs() {
        XCTAssertEqual(AccountLabel.title(email: "coach@example.com", name: "Pat Coach"), "coach@example.com")
        XCTAssertEqual(AccountLabel.subtitle(methods: [.google], email: "coach@example.com"), "Signed in with Google")
        XCTAssertEqual(AccountLabel.title(email: nil, name: nil), "Signed in")
    }

    // MARK: - Error wording

    func testAuthErrorsReadInCoachTerms() {
        XCTAssertEqual(AuthErrorWording.message(for: "Invalid login credentials"),
                       "That email and password don't match. Check both, or reset your password.")
        XCTAssertTrue(AuthErrorWording.message(for: "Email not confirmed")!.contains("Confirm your email"))
        XCTAssertTrue(AuthErrorWording.message(for: "Signups not allowed for this instance")!.contains("aren't open yet"))
        XCTAssertTrue(AuthErrorWording.message(for: "User already registered")!.contains("Sign in instead"))
        XCTAssertTrue(AuthErrorWording.message(for: "Password should be at least 6 characters")!.contains("at least 8"))
        XCTAssertEqual(AuthErrorWording.message(for: "Something odd"), "Something went wrong: Something odd")
    }

    func testCancellingSaysNothing() {
        XCTAssertNil(AuthErrorWording.message(for: "The user canceled the sign-in flow."))
    }

    // MARK: - Coach context

    func testSignalParametersWinOverTheSharedOnes() {
        CoachContext.set("platform", "ios")
        CoachContext.set("tier", "free")
        defer { CoachContext.set("tier", nil) }
        let merged = CoachContext.merged(with: ["tier": "pro", "source": "autofill"])
        XCTAssertEqual(merged["platform"], "ios")
        XCTAssertEqual(merged["tier"], "pro")
        XCTAssertEqual(merged["source"], "autofill")
        XCTAssertNotNil(merged["account"])   // device_only until a sign-in says otherwise
    }

    func testClearingAKeyRemovesIt() {
        CoachContext.set("tier", "pro")
        CoachContext.set("tier", nil)
        XCTAssertNil(CoachContext.parameters["tier"])
    }
}
