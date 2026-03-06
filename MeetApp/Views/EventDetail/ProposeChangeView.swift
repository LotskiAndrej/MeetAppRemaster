import SwiftUI

struct ProposeChangeView: View {
    let onSubmit: (_ proposedPlace: String?, _ proposedDate: Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var changePlace = false
    @State private var proposedPlace = ""
    @State private var changeDate = false
    @State private var proposedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    private var canSubmit: Bool {
        (changePlace && !proposedPlace.trimmingCharacters(in: .whitespaces).isEmpty) || changeDate
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Propose a new place") {
                    Toggle("Change place", isOn: $changePlace.animation())
                    if changePlace {
                        TextField("New place", text: $proposedPlace)
                    }
                }

                Section("Propose a new time") {
                    Toggle("Change date & time", isOn: $changeDate.animation())
                    if changeDate {
                        DatePicker(
                            "New date & time",
                            selection: $proposedDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }
                }
            }
            .navigationTitle("Propose Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        let place = changePlace ? proposedPlace.trimmingCharacters(in: .whitespaces) : nil
                        let date = changeDate ? proposedDate : nil
                        onSubmit(place, date)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
