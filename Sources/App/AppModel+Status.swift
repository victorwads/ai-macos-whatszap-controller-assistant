import AppKit
import Foundation

extension AppModel {
    func refreshStatus() {
        accessibilityTrusted = accessibility.isTrusted(prompt: false)
        whatsappRunning = accessibility.findWhatsAppApplication() != nil
        runtimeDescription = accessibility.currentAppIdentityDescription()

        appendLog("Accessibility trusted: \(accessibilityTrusted ? "yes" : "no")")
        appendLog("WhatsApp running: \(whatsappRunning ? "yes" : "no")")
        appendLog(runtimeDescription)
    }

    func updateLiveStatus() {
        accessibilityTrusted = accessibility.isTrusted(prompt: false)
        whatsappRunning = accessibility.findWhatsAppApplication() != nil
    }

    func startLiveStatusMonitoring() {
        liveStatusTask?.cancel()
        liveStatusTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await MainActor.run {
                    self.updateLiveStatus()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func requestAccessibilityPermission() {
        if accessibility.isTrusted(prompt: false) {
            accessibilityTrusted = true
            appendLog("Accessibility is already trusted for this app identity.")
            return
        }

        _ = accessibility.isTrusted(prompt: true)
        appendLog("Requested Accessibility permission from macOS.")
        appendLog("After enabling the app in System Settings, this app will relaunch itself.")
        appendLog("If permission resets after every build, configure a stable Apple Development signing identity for Debug.", level: .warning)
        refreshStatus()
        startPermissionMonitor()
    }

    func prepareForWhatsAppInspection() -> Bool {
        let trustedNow = accessibility.isTrusted(prompt: false)
        accessibilityTrusted = trustedNow
        whatsappRunning = accessibility.findWhatsAppApplication() != nil

        guard trustedNow else {
            appendLog("Cannot inspect WhatsApp before Accessibility permission is granted.", level: .warning)
            return false
        }

        guard whatsappRunning else {
            appendLog("Cannot inspect WhatsApp because it is not running.", level: .warning)
            return false
        }

        return true
    }

    func appendLog(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(level: level, message: message)
        logs.append(entry)
        Task {
            await IntegrationLogTailWriter.shared.append(entry: entry)
        }
    }

    private func startPermissionMonitor() {
        permissionMonitorTask?.cancel()
        waitingForAccessibilityRelaunch = true

        permissionMonitorTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<120 {
                guard !Task.isCancelled else { return }

                if self.accessibility.isTrusted(prompt: false) {
                    self.accessibilityTrusted = true
                    self.waitingForAccessibilityRelaunch = false
                    self.appendLog("Accessibility permission is now trusted. Relaunching app.")
                    self.relaunchCurrentApp()
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }

            self.waitingForAccessibilityRelaunch = false
            self.appendLog("Timed out waiting for Accessibility permission. Press Permission again after changing System Settings.", level: .warning)
        }
    }

    private func relaunchCurrentApp() {
        let bundleURL = Bundle.main.bundleURL

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try process.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            appendLog("Failed to relaunch app automatically: \(error.localizedDescription)", level: .error)
        }
    }
}
