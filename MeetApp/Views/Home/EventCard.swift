import SwiftUI
import FirebaseFirestore

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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Place and date
            VStack(alignment: .leading, spacing: 4) {
                Text(event.place)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(Self.dateFormatter.string(from: event.date.dateValue()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Metadata row
            HStack(spacing: 16) {
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
                    isDisabled: isPast
                ) {
                    onStatusChange(.going)
                }
                RSVPButton(
                    title: "Not Going",
                    systemImage: "xmark",
                    isSelected: currentStatus == .notGoing,
                    isDisabled: isPast
                ) {
                    onStatusChange(.notGoing)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.primary : Color.primary.opacity(0.08))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                .clipShape(Capsule())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
