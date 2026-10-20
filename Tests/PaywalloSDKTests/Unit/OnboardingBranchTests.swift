import XCTest
@testable import PaywalloSDK

final class OnboardingBranchTests: XCTestCase {

    private typealias Captured = (name: String, props: [String: AnyCodable], priority: EventPriority)

    /// Coleta os eventos num array protegido por lock (a closure é @escaping/async).
    private final class Box {
        private let lock = NSLock()
        private var items: [Captured] = []
        func add(_ c: Captured) { lock.lock(); items.append(c); lock.unlock() }
        var all: [Captured] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func makeManager(distinctId: String = "user-1") -> (OnboardingManager, Box) {
        let box = Box()
        let manager = OnboardingManager()
        manager.injectDeps(
            trackEvent: { name, props, priority in box.add((name, props, priority)) },
            distinctIdProvider: { distinctId }
        )
        return (manager, box)
    }

    func testBranch_emitsOnboardingBranchEvent() async throws {
        let (manager, box) = makeManager()
        try await manager.branch(key: "objetivo", value: "perder_peso")

        XCTAssertEqual(box.all.count, 1)
        let e = box.all[0]
        XCTAssertEqual(e.name, "onboarding")
        XCTAssertEqual(e.props["family"]?.value as? String, "onboarding")
        XCTAssertEqual(e.props["type"]?.value as? String, "branch")
        XCTAssertEqual(e.props["key"]?.value as? String, "objetivo")
        XCTAssertEqual(e.props["value"]?.value as? String, "perder_peso")
        XCTAssertEqual(e.priority, .normal)
    }

    func testBranch_trimsKeyAndValue() async throws {
        let (manager, box) = makeManager()
        try await manager.branch(key: "  objetivo \n", value: " perder_peso ")

        XCTAssertEqual(box.all.first?.props["key"]?.value as? String, "objetivo")
        XCTAssertEqual(box.all.first?.props["value"]?.value as? String, "perder_peso")
    }

    func testBranch_length64Emits_65DoesNotEmitNorThrow() async throws {
        let (manager, box) = makeManager()
        try await manager.branch(key: String(repeating: "a", count: 64), value: "v")
        XCTAssertEqual(box.all.count, 1)

        try await manager.branch(key: String(repeating: "a", count: 65), value: "v")
        try await manager.branch(key: "k", value: String(repeating: "b", count: 65))
        XCTAssertEqual(box.all.count, 1)
    }

    func testBranch_emptyOrBlank_doesNotEmit() async throws {
        let (manager, box) = makeManager()
        try await manager.branch(key: "", value: "v")
        try await manager.branch(key: "k", value: "")
        try await manager.branch(key: "   ", value: "v")
        try await manager.branch(key: "k", value: "   ")
        XCTAssertTrue(box.all.isEmpty)
    }

    func testBranch_notInitialized_throws() async {
        let manager = OnboardingManager()
        do {
            try await manager.branch(key: "k", value: "v")
            XCTFail("esperava OnboardingError")
        } catch let error as OnboardingError {
            XCTAssertEqual(error.code, OnboardingErrorCode.notInitialized)
        } catch {
            XCTFail("erro inesperado: \(error)")
        }
    }

    func testBranch_emptyDistinctId_doesNotEmit() async throws {
        let (manager, box) = makeManager(distinctId: "")
        try await manager.branch(key: "k", value: "v")
        XCTAssertTrue(box.all.isEmpty)
    }
}
