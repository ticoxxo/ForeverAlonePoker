import Foundation
import UIKit

/// Downloads skin files on a background `URLSession`, so a purchased set
/// keeps downloading when the player leaves the app (tdr/0012). Each request
/// is bridged to async/await; the delegate moves the file somewhere we own
/// before returning, because the system deletes it afterwards.
///
/// If the app is terminated mid-download, the continuations are gone; the
/// next `SkinStore.syncAssets()` simply asks again.
nonisolated final class BackgroundSkinDownloader: NSObject, AssetDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    static let sessionIdentifier = "\(Bundle.main.bundleIdentifier ?? "ForeverAlonePoker").skins"
    static let shared = BackgroundSkinDownloader()

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<URL, any Error>] = [:]
    private var finishedEventsHandler: (() -> Void)?
    private var createdSession: URLSession?

    /// Created on first use; one background session per identifier per process.
    private var session: URLSession {
        lock.withLock {
            if let createdSession { return createdSession }
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            // Bounds the parallel transfers of a 52-card set.
            configuration.httpMaximumConnectionsPerHost = 6
            let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            createdSession = created
            return created
        }
    }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url)
            lock.withLock { continuations[task.taskIdentifier] = continuation }
            task.resume()
        }
    }

    /// From `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    func handleEvents(completionHandler: @escaping () -> Void) {
        lock.withLock { finishedEventsHandler = completionHandler }
        _ = session  // Reconnects to the background session.
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let result: Result<URL, any Error>
        if status == 200 {
            let owned = FileManager.default.temporaryDirectory.appending(path: "skin-\(UUID().uuidString)")
            result = Result { try FileManager.default.moveItem(at: location, to: owned); return owned }
        } else {
            result = .failure(SkinAssetError.badResponse(status: status))
        }
        take(downloadTask.taskIdentifier)?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Success was already delivered by didFinishDownloadingTo.
        guard let error else { return }
        take(task.taskIdentifier)?.resume(throwing: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock {
            defer { finishedEventsHandler = nil }
            return finishedEventsHandler
        }
        guard let handler else { return }
        DispatchQueue.main.async(execute: handler)
    }

    private func take(_ identifier: Int) -> CheckedContinuation<URL, any Error>? {
        lock.withLock { continuations.removeValue(forKey: identifier) }
    }
}

/// Lets the system relaunch the app to finish background skin downloads.
final class SkinDownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundSkinDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundSkinDownloader.shared.handleEvents(completionHandler: completionHandler)
    }
}
