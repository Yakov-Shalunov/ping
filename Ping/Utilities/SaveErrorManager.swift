import SwiftUI
import SwiftData

@Observable
@MainActor
final class SaveErrorManager {
    private(set) var currentError: String?

    func backgroundSave(_ context: ModelContext, contactName: String, applying mutations: @escaping () -> Void = {}) {
        Task { @MainActor in
            mutations()
            do {
                try context.save()
            } catch {
                let message = "Save failed for \(contactName)"
                currentError = message
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if self.currentError == message {
                        self.currentError = nil
                    }
                }
            }
        }
    }

    func dismissError() {
        withAnimation {
            currentError = nil
        }
    }
}
