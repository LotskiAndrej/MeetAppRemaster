import SwiftUI
import FirebaseFirestore

/// Returns a human-friendly date string: "Today, 14:30", "Tomorrow, …", "Yesterday, …", or a medium date otherwise.
func formatEventDate(_ date: Date) -> String {
    let cal = Calendar.current
    let tf = DateFormatter()
    tf.dateFormat = "HH:mm"
    let time = tf.string(from: date)
    if cal.isDateInToday(date)     { return "Today, \(time)" }
    if cal.isDateInTomorrow(date)  { return "Tomorrow, \(time)" }
    if cal.isDateInYesterday(date) { return "Yesterday, \(time)" }
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}

struct EventCard: View {
    let event: Event
    let commentCount: Int
    let pendingProposalCount: Int
    let currentUserId: String
    let onStatusChange: (ParticipantStatus) -> Void

    private var isPast: Bool {
        event.date.dateValue() < Date()
    }

    private var currentStatus: ParticipantStatus? {
        event.participants[currentUserId]
    }

    private var goingCount: Int {
        event.participants.values.filter { $0 == .going }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Place and date
            VStack(alignment: .leading, spacing: 4) {
                Text(event.place)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(formatEventDate(event.date.dateValue()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Metadata row
            HStack(spacing: 16) {
                Label("\(goingCount) going", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                if commentCount > 0 {
                    Label("\(commentCount)", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if pendingProposalCount > 0 {
                    Label("\(pendingProposalCount) proposal\(pendingProposalCount == 1 ? "" : "s")",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if isPast {
                    Text("Past event")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // RSVP buttons
            HStack(spacing: 10) {
                RSVPButton(
                    title: "Going",
                    systemImage: "checkmark",
                    isSelected: currentStatus == .going,
                    isDisabled: isPast,
                    selectedColor: .green
                ) {
                    onStatusChange(currentStatus == .going ? .pending : .going)
                }
                RSVPButton(
                    title: "Not Going",
                    systemImage: "xmark",
                    isSelected: currentStatus == .notGoing,
                    isDisabled: isPast,
                    selectedColor: .red
                ) {
                    onStatusChange(currentStatus == .notGoing ? .pending : .notGoing)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RSVPButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let selectedColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? selectedColor : selectedColor.opacity(0.1))
                .foregroundStyle(isSelected ? Color.white : selectedColor)
                .clipShape(Capsule())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
