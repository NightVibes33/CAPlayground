import SwiftUI

struct StatePanel: View {
    @Binding var project: CAProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("States").font(.headline).padding(12)
            Divider()
            List(project.states, id: \.self) { state in
                HStack {
                    Image(systemName: state == project.activeState ? "circle.inset.filled" : "circle")
                        .foregroundStyle(state == project.activeState ? CATheme.accent : .secondary)
                    Text(state)
                    Spacer()
                    Text("\(project.stateOverrides[state]?.count ?? 0)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(state)
                .contentShape(Rectangle())
                .onTapGesture { project.activeState = state }
            }
            .listStyle(.plain)
        }
        .caPanel()
    }
}
