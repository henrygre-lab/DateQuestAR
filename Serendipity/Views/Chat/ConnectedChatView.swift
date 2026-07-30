import SwiftUI

// MARK: - Display model
//
// There is no messaging model in this app — no `Message` type, no Firestore
// collection, no send path. This struct exists so the surface can be built and
// reviewed; it is display-only and deliberately minimal. Replace it with the
// real model when messaging is designed, and this view should need no layout
// changes.

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isOutgoing: Bool

    init(id: UUID = UUID(), text: String, isOutgoing: Bool) {
        self.id = id
        self.text = text
        self.isOutgoing = isOutgoing
    }
}

/// Post-NameDrop conversation (docs/DESIGN_SYSTEM.md §6 row 4). The only screen
/// where the partner photo is unblurred and the name resolves.
///
/// Presentational: the caller supplies the transcript and handles sending, so
/// the composer is not a dead end wherever it is wired up. **Not currently
/// reachable** — see docs/UI_REWORK_STATUS.md.
struct ConnectedChatView: View {
    let name: String
    let tier: UserProfile.TrustLevel
    let isIDVerified: Bool
    let sharedInterests: [String]
    let messages: [ChatMessage]
    /// Nil when no live distance is available — the label then reads
    /// "Still nearby" with no figure. A distance is never approximated.
    var proximityLabel: String?
    var onSend: (String) -> Void
    var onOpenSafety: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @State private var draft = ""

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 12) {
                        connectedCard
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding(DQSpace.gutter)
                }
                safetyPrompt
                    .padding(.horizontal, DQSpace.gutter)
                composer
                    .padding(.horizontal, DQSpace.gutter)
                    .padding(.top, 11)
                    .padding(.bottom, DQSpace.safeBottom)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            DQIconButton(symbol: "chevron.left", label: "Back") { dismiss() }

            // Fully revealed — this is the one surface where the photo is
            // unblurred and the name resolves.
            PartnerPhotoPlaceholder(initials: name.dqInitials, glyphSize: 16)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(p.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(DQFont.titleS)
                        .tracking(DQFont.trackTitleS)
                        .foregroundStyle(p.text)
                    if isIDVerified {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(p.verify))
                    }
                }
                HStack(spacing: 6) {
                    LiveDot(size: 6)
                    Text(proximityLabel ?? "Still nearby")
                        .font(DQFont.uiSized(10, .semibold))
                        .tracking(DQFont.track(10, em: 0.06))
                        .foregroundStyle(p.text2)
                }
            }

            Spacer(minLength: 0)

            DQIconButton(symbol: "shield", label: "Safety options", action: onOpenSafety)
        }
        .padding(.horizontal, DQSpace.gutter)
        .padding(.top, DQSpace.safeTop)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }

    // MARK: - Summary

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: DQSpace.tight) {
            Text("You connected")
                .font(DQFont.labelSized(9))
                .tracking(DQFont.track(9, em: 0.2))
                .textCase(.uppercase)
                .foregroundStyle(p.text3)

            Text("Both of you dropped names. Photos are fully revealed for this encounter only.")
                .font(DQFont.bodyS)
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)

            if !sharedInterests.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(sharedInterests, id: \.self) { interest in
                        DQChip(text: interest)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(DQSpace.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .dqShadow(.small(theme))
    }

    // MARK: - Safety prompt (persistent, §8)

    private var safetyPrompt: some View {
        HStack(spacing: 11) {
            Image(systemName: "shield")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(p.text3)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(p.text3, lineWidth: 1.5))

            Text("Meeting up? Share your live location with a friend from the safety menu.")
                .font(DQFont.uiSized(11, .medium))
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DQSpace.gutter)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .font(DQFont.body)
                .foregroundStyle(p.text)
                .lineLimit(1...4)
                .padding(.leading, 18)
                .accessibilityLabel("Message \(name)")

            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                onSend(text)
                draft = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(p.ember))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send")
        }
        .padding(8)
        .background(Capsule().fill(p.surface2))
        .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
    }
}

// MARK: - Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    @Environment(\.dq) private var p

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 40) }

            Text(message.text)
                .font(DQFont.body)
                .foregroundStyle(message.isOutgoing ? .white : p.text)
                .padding(.horizontal, DQSpace.gutter)
                .padding(.vertical, 13)
                .background {
                    if message.isOutgoing {
                        BubbleShape(isOutgoing: true).fill(p.ember)
                    } else {
                        BubbleShape(isOutgoing: false).fill(p.surface)
                            .overlay(BubbleShape(isOutgoing: false).strokeBorder(p.line, lineWidth: 1))
                    }
                }

            if !message.isOutgoing { Spacer(minLength: 40) }
        }
        .accessibilityLabel("\(message.isOutgoing ? "You said" : "They said"): \(message.text)")
    }
}

/// `rRow` on three corners, tightened on the corner nearest the speaker.
private struct BubbleShape: InsettableShape {
    let isOutgoing: Bool
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = DQRadius.row
        let tail: CGFloat = 7
        return Path(
            roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount),
            cornerRadii: RectangleCornerRadii(
                topLeading: r,
                bottomLeading: isOutgoing ? r : tail,
                bottomTrailing: isOutgoing ? tail : r,
                topTrailing: r
            )
        )
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
