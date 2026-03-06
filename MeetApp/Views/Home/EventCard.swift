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
    var isOrganizer: Bool = false
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.place)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(formatEventDate(event.date.dateValue()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isOrganizer {
                    Text("Host")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }

            // Metadata row
            HStack(spacing: 12) {
                if goingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text("\(goingCount) going")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
                if commentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        Text("\(commentCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if pendingProposalCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("\(pendingProposalCount) proposal\(pendingProposalCount == 1 ? "" : "s")")
                    }
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
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? selectedColor : selectedColor.opacity(0.1))
        .foregroundStyle(isSelected ? Color.white : selectedColor)
        .clipShape(Capsule())
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .highPriorityGesture(
            isDisabled ? nil : TapGesture().onEnded { action() }
        )
    }
}
