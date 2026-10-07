import Foundation

/// Polls `condition` until it is true or `timeout` elapses. Returns the final
/// value so callers can `#expect(await eventually { ... })`.
///
/// Message delivery in the app goes through actors and async streams, so a
/// test cannot assert immediately after an action; it waits for the state it
/// expects instead of sleeping a fixed time.
@MainActor
func eventually(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
