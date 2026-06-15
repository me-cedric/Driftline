import Foundation

// MARK: - SandboxError

public enum SandboxError: Error, Sendable, Equatable {
    case notAllowed(path: String, allowedRoots: [String])
}

// MARK: - LocalPathSandbox

/// Validates that local file paths stay within allowed roots.
/// Both candidate and root paths are canonicalized before comparison
/// to guard against symlink-escape and `..` traversal attacks.
public struct LocalPathSandbox: Sendable {
    /// Resolved absolute path components of each allowed root.
    public let allowedRoots: [String]

    public init(roots: [String]) {
        if roots.isEmpty {
            // Default to the user's Downloads directory.
            let downloadsURLs = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            let fallback = downloadsURLs.first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
            self.allowedRoots = [Self.canonical(fallback.path)]
        } else {
            self.allowedRoots = roots.map { Self.canonical($0) }
        }
    }

    // MARK: Validation

    /// Return the canonical path if it is contained within any allowed root, or throw.
    public func validatedPath(_ path: String) throws -> String {
        let candidate = Self.canonical(path)
        guard self.allowedRoots.contains(where: { Self.isContained(candidate: candidate, within: $0) }) else {
            throw SandboxError.notAllowed(path: path, allowedRoots: self.allowedRoots)
        }
        return candidate
    }

    /// Validate a path that may not exist yet (e.g. download destination).
    /// Canonicalises the parent directory and re-appends the filename.
    public func validatedNewPath(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let parentURL = url.deletingLastPathComponent()
        let canonicalParent = Self.canonical(parentURL.path)
        let filename = url.lastPathComponent
        let candidate = (canonicalParent as NSString).appendingPathComponent(filename)
        guard self.allowedRoots.contains(where: { Self.isContained(candidate: canonicalParent, within: $0) }) else {
            throw SandboxError.notAllowed(path: path, allowedRoots: self.allowedRoots)
        }
        return candidate
    }

    // MARK: Helpers

    /// Resolve symlinks, `.`, and `..`.
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    /// Path-component containment: candidate must START with root's components.
    /// Prevents `/Users/x/Downloads-evil` matching root `/Users/x/Downloads`.
    private static func isContained(candidate: String, within root: String) -> Bool {
        let rootComponents = URL(fileURLWithPath: root).pathComponents
        let candidateComponents = URL(fileURLWithPath: candidate).pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy { $0 == $1 }
    }
}
