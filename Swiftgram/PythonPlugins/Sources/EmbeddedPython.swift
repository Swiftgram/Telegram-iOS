#if canImport(Python)
import Python
#endif
import Foundation
import ZipArchive

/// Thin Swift wrapper around the embedded CPython 3.11 interpreter.
///
/// Compiled against the `Python` module when `Python.xcframework` is linked; otherwise every call
/// is a no-op and plugins stay in stub mode.
///
/// Only `PyRun_SimpleString` and a few error helpers are used. All plugin logic is Python
/// (`stdlib/trollgram_host.py`): Swift sends one base64 JSON request per call and reads one JSON
/// result from a file, which keeps the native side free of `PyObject` plumbing.
///
/// Threading: CPython is initialised on the main thread, which then owns the GIL. Every call into the
/// interpreter must therefore happen on the main thread; `call(_:)` refuses to run anywhere else.
final class EmbeddedPython {
    static let shared = EmbeddedPython()

    private var isStarted = false
    private var hasFailed = false
    private var resultPath = ""

    private init() {}

    var isAvailable: Bool {
        #if canImport(Python)
        return true
        #else
        return false
        #endif
    }

    /// Starts CPython with `PYTHONHOME` pointing at the extracted stdlib. Safe to call repeatedly.
    func start(dataDirectory: String) -> Bool {
        #if canImport(Python)
        if self.isStarted {
            return true
        }
        if self.hasFailed || !Thread.isMainThread {
            return false
        }
        guard let resources = Bundle.main.resourcePath else {
            self.hasFailed = true
            return false
        }
        guard let home = self.prepareStdlib(resources: resources) else {
            NSLog("[TrollGram] Python stdlib is unavailable")
            self.hasFailed = true
            return false
        }
        let stdlib = home + "/lib/python3.11"
        // Plugin files are loaded by path (never put on `sys.path`), so a plugin named like a stdlib
        // module cannot shadow it. `home` holds the bundled SDK (`base_plugin`, `trollgram_host`, ...).
        setenv("PYTHONHOME", home, 1)
        setenv("PYTHONPATH", home + ":" + stdlib + ":" + stdlib + "/lib-dynload", 1)
        setenv("TROLLGRAM_DATA_DIR", dataDirectory, 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)

        Py_Initialize()

        if let error = self.run("import encodings, os, sys, json, base64, trollgram_host") {
            NSLog("[TrollGram] Python bootstrap failed: \(error)")
            self.hasFailed = true
            return false
        }
        self.resultPath = dataDirectory + "/.call_result.json"
        self.isStarted = true
        return true
        #else
        return false
        #endif
    }

    /// Extracts `python.zip` from the app bundle and returns the root `PYTHONHOME` expects
    /// (`lib/python3.11` lives directly inside it). The archive is extracted again whenever a different
    /// build is installed, so SDK updates are picked up.
    private func prepareStdlib(resources: String) -> String? {
        let fileManager = FileManager.default
        let support = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()) + "/TrollGram"
        let home = support + "/python"
        guard let archive = Bundle.main.path(forResource: "python", ofType: "zip") else {
            NSLog("[TrollGram] python.zip is not bundled (looked in \(resources))")
            return nil
        }

        let archiveSize = ((try? fileManager.attributesOfItem(atPath: archive))?[.size] as? NSNumber)?.int64Value ?? 0
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "") + "/" + (info?["CFBundleVersion"] as? String ?? "")
        let stamp = "\(archiveSize)|\(version)"
        let stampPath = home + "/.bundle-stamp"
        let installedStamp = try? String(contentsOfFile: stampPath, encoding: .utf8)
        if installedStamp == stamp && fileManager.fileExists(atPath: home + "/lib/python3.11/os.py") {
            return home
        }

        do {
            try fileManager.createDirectory(atPath: support, withIntermediateDirectories: true)
            try? fileManager.removeItem(atPath: home)
            guard SSZipArchive.unzipFile(atPath: archive, toDestination: home) else {
                NSLog("[TrollGram] Failed to extract python.zip")
                return nil
            }
            try stamp.write(toFile: stampPath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[TrollGram] Failed to prepare python stdlib: \(error)")
            return nil
        }
        return fileManager.fileExists(atPath: home + "/lib/python3.11/os.py") ? home : nil
    }

    /// Executes a Python snippet. Returns an error description on failure.
    @discardableResult
    private func run(_ code: String) -> String? {
        #if canImport(Python)
        if PyRun_SimpleString(code) == 0 {
            return nil
        }
        var message = "unknown Python error"
        if let type = PyErr_Occurred(), let text = PyObject_Str(type), let cString = PyUnicode_AsUTF8(text) {
            message = String(cString: cString)
        }
        PyErr_Clear()
        return message
        #else
        return "Python runtime is not linked"
        #endif
    }

    /// Sends `request` to `trollgram_host.call` and returns its JSON result, or `nil` when the interpreter
    /// is not running, the call is not on the main thread, or Python could not produce a result.
    func call(_ request: [String: Any]) -> [String: Any]? {
        #if canImport(Python)
        guard self.isStarted, Thread.isMainThread else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(request),
              let data = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            return nil
        }
        try? FileManager.default.removeItem(atPath: self.resultPath)
        // base64 contains only [A-Za-z0-9+/=], so it is safe inside a Python string literal.
        let payload = data.base64EncodedString()
        let escapedPath = self.resultPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        if let error = self.run("import trollgram_host\ntrollgram_host.call('\(payload)', '\(escapedPath)')") {
            NSLog("[TrollGram] Python call failed: \(error)")
            return nil
        }
        guard let raw = FileManager.default.contents(atPath: self.resultPath),
              let object = try? JSONSerialization.jsonObject(with: raw, options: []),
              let result = object as? [String: Any] else {
            return nil
        }
        return result
        #else
        return nil
        #endif
    }
}
