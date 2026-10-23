import Foundation

@main
struct SetupSmoke {
    @MainActor static func main() async {
        let preview = InstallationManager(previewStep: 2)
        precondition(preview.currentStep == 2 && preview.isPreview)
        preview.install()
        preview.autoEnableInputSource()
        precondition(!preview.isInstalling && !preview.isSourceAdded && !preview.isCurrentSource)
        let manager = InstallationManager()
        let wasInstalled = manager.isInstalled
        manager.install()
        for _ in 0..<30 {
            if !manager.isInstalling { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        precondition(!manager.isInstalling)
        precondition(manager.errorMessage?.contains("缺少输入法组件") == true)
        precondition(manager.currentStep == 0, "Failure must never advance the wizard")
        precondition(manager.isInstalled == wasInstalled, "Missing payload must not modify installation")
        print("PASS: isolated preview, missing-payload error, retryable state, no false success")
    }
}
