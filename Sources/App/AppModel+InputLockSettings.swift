import Combine
import Foundation

extension AppModel {
    func loadExperimentalInputLockSetting() {
        experimentalInputLockEnabled = InputLockSettingsRepository.shared.load()

        $experimentalInputLockEnabled
            .dropFirst()
            .sink { [weak self] value in
                guard self != nil else { return }
                InputLockSettingsRepository.shared.save(value)
            }
            .store(in: &cancellables)
    }
}
