import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CreateEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var place = ""
    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let eventService = EventService()

    private var isValid: Bool {
        !place.trimmingCharacters(in: .whitespaces).isEmpty && date > Date()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Form {
                    Section("Event Details") {
                        TextField("Place", text: $place)
                        DatePicker(
                            "Date & Time",
                            selection: $date,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createEvent()
                    }
                    .disabled(!isValid || isSubmitting)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func createEvent() {
        guard let circleId = appState.activeCircle?.id,
              let userId = appState.authService.currentUser?.uid else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let trimmedPlace = place.trimmingCharacters(in: .whitespaces)
            let event = Event(
                circleId: circleId,
                organizerId: userId,
                place: trimmedPlace,
                date: Timestamp(date: date),
                createdAt: Timestamp(date: Date()),
                participants: [:]
            )
            try eventService.createEvent(event)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
