import Combine
import Foundation

extension AppModel {
    func loadExperimentalInputLockSetting() {
        experimentalInputLockEnabled = UserDefaults.standard.bool(forKey: experimentalInputLockEnabledDefaultsKey)

        $experimentalInputLockEnabled
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                UserDefaults.standard.set(value, forKey: self.experimentalInputLockEnabledDefaultsKey)
            }
            .store(in: &cancellables)
    }
}

