import SwiftUI

/// Progress of the running brew command, with its output behind a disclosure.
struct OperationStatusView: View {
    let operation: BrewOperation
    @Environment(AppModel.self) private var model
    @ViewState private var showsOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(operation.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if operation.isRunning {
                    Button("Cancel") { operation.cancel() }
                        .controlSize(.small)
                } else {
                    Button {
                        model.dismissOperation()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }
            }

            DisclosureGroup(isExpanded: $showsOutput) {
                OutputLog(text: operation.output)
            } label: {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: showsOutput) { _, expanded in
                if expanded { model.keepOperationVisible() }
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .contain)
        .onChange(of: operation.state) { _, state in
            if case .failed = state { showsOutput = true }
        }
    }

    private var detail: String? {
        switch operation.state {
        case .running: operation.lastLine
        case .failed: operation.failureSummary
        default: nil
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch operation.state {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
        }
    }
}

private struct OutputLog: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "Waiting for output…" : text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                Color.clear.frame(height: 1).id("end")
            }
            .frame(height: 140)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onChange(of: text) { proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}
