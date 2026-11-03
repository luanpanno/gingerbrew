import GingerbrewCore
import SwiftUI

struct PackageRow: View {
    let package: Package

    var body: some View {
        HStack(spacing: 10) {
            PackageIcon(package: package, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(package.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let summary = package.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }

    @ViewBuilder
    private var trailing: some View {
        if package.isOutdated {
            HStack(spacing: 4) {
                Text(package.latestVersion ?? "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel("Update available: \(package.latestVersion ?? "")")
        } else if let version = package.installedVersion {
            Text(version)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            Text(package.kind == .cask ? "App" : "Formula")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
    }
}

/// The app icon for installed casks; an SF Symbol otherwise.
struct PackageIcon: View {
    let package: Package
    let size: CGFloat

    var body: some View {
        if let image = PackageMetadata.icon(for: package) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(.quaternary)
                .frame(width: size * 0.86, height: size * 0.86)
                .overlay {
                    Image(systemName: package.kind == .cask ? "app.dashed" : "terminal")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
