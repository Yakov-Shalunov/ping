import SwiftUI

struct PersonRowView: View {
    let contact: Contact
    let globalDefault: Int

    private var overdueDays: Int? {
        contact.daysOverdue(globalDefault: globalDefault)
    }

    private var statusIndicator: (color: Color, label: String)? {
        guard let days = overdueDays else { return nil }
        if days > 0 {
            return (.red, "\(days)d overdue")
        } else if days > -7 {
            return (.orange, "Due soon")
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                if !contact.affiliations.isEmpty {
                    Text(contact.affiliations.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if let status = statusIndicator {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                            .help(status.label)
                    }
                }

                if !contact.locationSummary.isEmpty {
                    Text(contact.locationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !(contact.tags ?? []).isEmpty {
                    HStack(spacing: 4) {
                        ForEach((contact.tags ?? []).prefix(3)) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tag.color.opacity(0.15))
                                .foregroundStyle(tag.color)
                                .clipShape(Capsule())
                        }
                        if (contact.tags ?? []).count > 3 {
                            Text("+\((contact.tags ?? []).count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Contact Avatar

struct ContactAvatar: View {
    let contact: Contact
    let size: CGFloat

    var body: some View {
        if let data = contact.photoData,
           let uiImage = PlatformImage(data: data) {
            Image(platformImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)
                .overlay {
                    Text(contact.displayName.prefix(1).uppercased())
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }
}

// MARK: - Cross-platform image helpers

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#endif
