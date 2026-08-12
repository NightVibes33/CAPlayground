import SwiftUI

private struct RoadmapEntry: Identifiable {
    let id: Int
    let title: String
    let status: String
    let description: String
    let isComplete: Bool
}

struct RoadmapView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Roadmap")
                        .font(.system(size: 44, weight: .bold))
                    Text("What's cooking in CAPlayground? (Last Updated: 17th November, 2025)")
                        .foregroundStyle(.secondary)
                }

                Picker("Month", selection: $selectedMonth) {
                    Text("Month 1").tag(1)
                    Text("Month 2").tag(2)
                    Text("Month 3").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                VStack(spacing: 24) {
                    ForEach(months[selectedMonth - 1]) { item in
                        roadmapCard(item)
                    }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 64)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Roadmap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roadmapCard(_ item: RoadmapEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    numberAndTitle(item)
                    Spacer()
                    status(item)
                }
                VStack(alignment: .leading, spacing: 12) {
                    numberAndTitle(item)
                    status(item)
                }
            }
            Text(item.description)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .caPanel()
    }

    private func numberAndTitle(_ item: RoadmapEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(item.id)")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(CATheme.accent, in: RoundedRectangle(cornerRadius: 8))
            Text(item.title).font(.title2.weight(.semibold))
        }
    }

    private func status(_ item: RoadmapEntry) -> some View {
        Text(item.status)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(item.isComplete ? CATheme.accent : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(item.isComplete ? Color.black : Color.primary)
    }
}
