import SwiftUI

private struct RoadmapEntry: Identifiable {
    let id: Int
    let title: String
    let status: String
    let description: String
    let isComplete: Bool
}

struct RoadmapView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedMonth = 3

    private let months: [[RoadmapEntry]] = [
        [
            .init(id: 1, title: "The Start", status: "Done: 24th August, 2025", description: "Starting the project on 24th August, 2025 because Lemin said it's time for a second wallpaper competition. Creating the project.", isComplete: true),
            .init(id: 2, title: "Projects and Base Editor", status: "Done: 24th August, 2025", description: "Projects page, base editor, and create .ca files.", isComplete: true),
            .init(id: 3, title: "Viewing and Editing Layers", status: "Done: 5th September, 2025", description: "Viewing and Editing layers of a Core Animation file. Exporting the .ca file.", isComplete: true),
            .init(id: 4, title: "Core Animation Layer Properties", status: "Done: 5th September, 2025", description: "Adjusting position, bounds, opacity, rotation, and more of layers.", isComplete: true),
            .init(id: 5, title: "Creating Animations, Viewing and Editing States", status: "Done: 22nd September, 2025", description: "Creating state transitions and keyframe animations.", isComplete: true),
            .init(id: 6, title: "CAPlayground App", status: "Skipped", description: "CAPlayground app to work inside an app.", isComplete: false)
        ],
        [
            .init(id: 1, title: "Mobile Editor", status: "Done: 4th October, 2025", description: "Edit wallpapers on mobile, such as your iPhone or iPad.", isComplete: true),
            .init(id: 2, title: "Wallpaper Gallery", status: "Done: 5th October, 2025", description: "Wallpaper Gallery to showcase your wallpapers and browse the CAPlayground community's wallpapers.", isComplete: true),
            .init(id: 3, title: "Gradient Layers", status: "Done: 7th October, 2025", description: "Create gradients with the modes radial, axial, and conic.", isComplete: true),
            .init(id: 4, title: "Cloud Projects", status: "Done: 18th October, 2025", description: "Sync your projects to Google Drive to access projects on multiple devices.", isComplete: true),
            .init(id: 5, title: "Emitters Support", status: "Done: 24th October, 2025", description: "Create emitters layers and cells to emit particles.", isComplete: true),
            .init(id: 6, title: "Parallax Effect (Beta)", status: "Done: 28th October, 2025", description: "Create wallpapers with Parallax Effect (Gyroscope) for iOS 26. Will need to make sublayers support because of this.", isComplete: true)
        ],
        [
            .init(id: 1, title: "Replicator Layers", status: "Done: 3rd November, 2025", description: "Create replicator layers to duplicate and arrange layers in patterns.", isComplete: true),
            .init(id: 2, title: "Blending Modes", status: "Done: 12th November, 2025", description: "Create a blending effect between 2+ layers such as darken, lighten and more.", isComplete: true),
            .init(id: 3, title: "Filters", status: "Done: 12th November, 2025", description: "Add filters to layers for effects, such as guassin blur, contrast, and more.", isComplete: true),
            .init(id: 4, title: "Sync Video with State", status: "Done: 17th November, 2025", description: "Sync video with state transitions to have a video start on a state and end on another.", isComplete: true),
            .init(id: 5, title: "Performance Improvements", status: "In Progress", description: "Fix bugs, improve performance, reducing crashes and lagging on devices with optimisation settings.", isComplete: false)
        ]
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Project Roadmap").font(.system(size: sizeClass == .compact ? 40 : 52, weight: .bold))
                            Text("What's cooking in CAPlayground? (Last Updated: 17th November, 2025)").foregroundStyle(.secondary)
                        }.padding(.bottom, 24)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { monthButtons }
                            VStack(alignment: .leading, spacing: 8) { monthButtons }
                        }.padding(.bottom, 40)

                        VStack(spacing: 24) { ForEach(months[selectedMonth - 1]) { item in roadmapCard(item) } }
                    }
                    .frame(maxWidth: 1152, alignment: .leading)
                    .padding(.horizontal, sizeClass == .compact ? 12 : 24)
                    .padding(.top, sizeClass == .compact ? 112 : 144)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity)
                    CAWebsiteFooter()
                }
            }
            .background(CATheme.background(scheme).ignoresSafeArea())
            CAWebsiteNavigation().padding(.horizontal, sizeClass == .compact ? 16 : 24).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var monthButtons: some View { monthButton(1); monthButton(2); monthButton(3) }

    private func monthButton(_ month: Int) -> some View {
        Button("Month \(month)") { selectedMonth = month }.buttonStyle(CAWebButtonStyle(variant: selectedMonth == month ? .accent : .outline))
    }

    private func roadmapCard(_ item: RoadmapEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { numberAndTitle(item); Spacer(); status(item) }
                VStack(alignment: .leading, spacing: 12) { numberAndTitle(item); status(item) }
            }
            Text(item.description).font(sizeClass == .compact ? .subheadline : .body).foregroundStyle(.secondary)
        }
        .padding(sizeClass == .compact ? 20 : 24).frame(maxWidth: .infinity, alignment: .leading)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme), lineWidth: 1) }
    }

    private func numberAndTitle(_ item: RoadmapEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(item.id)").font(.headline).foregroundStyle(CATheme.foreground(scheme))
                .frame(width: sizeClass == .compact ? 32 : 36, height: sizeClass == .compact ? 32 : 36)
                .background(CATheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Text(item.title).font(.system(size: sizeClass == .compact ? 20 : 24, weight: .semibold))
        }
    }

    private func status(_ item: RoadmapEntry) -> some View {
        Text(item.status).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(item.isComplete ? CATheme.accent.opacity(0.14) : CATheme.muted(scheme).opacity(0.55), in: Capsule())
            .foregroundStyle(item.isComplete ? CATheme.accent : .secondary)
            .overlay(Capsule().stroke(item.isComplete ? CATheme.accent.opacity(0.3) : CATheme.border(scheme)))
    }
}
