//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//  Pulau fork: dynamic tab list (Home / Lyrics / Focus / Assistant / Shelf),
//  stable identities and a tighter icon-only pill.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let label: String
    let icon: String
    let view: NotchViews
    var id: NotchViews { view }
}

/// Tabs shown in the open notch, filtered by the user's settings.
var tabs: [TabModel] {
    var result: [TabModel] = [TabModel(label: "Home", icon: "house.fill", view: .home)]
    if Defaults[.pulauLyricsTab] {
        result.append(TabModel(label: "Lyrics", icon: "quote.bubble.fill", view: .lyrics))
    }
    // Never show to-dos, clipboard history or chat on the lock screen.
    let locked = PulauLockScreen.isLocked
    if Defaults[.pulauFocusTab] && !locked {
        result.append(TabModel(label: "Focus", icon: "timer", view: .focus))
    }
    if Defaults[.pulauAssistantTab] && !locked {
        result.append(TabModel(label: "Assistant", icon: "sparkles", view: .assistant))
    }
    if Defaults[.boringShelf] {
        result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    return result
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation

    // Re-render when tab toggles change.
    @Default(.pulauLyricsTab) private var lyricsTab
    @Default(.pulauFocusTab) private var focusTab
    @Default(.pulauAssistantTab) private var assistantTab
    @Default(.boringShelf) private var shelfTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let isSelected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    withAnimation(PulauTheme.spring) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    Capsule()
                        .fill(isSelected ? Color(nsColor: .secondarySystemFill) : Color.clear)
                        .matchedGeometryEffect(id: "capsule", in: animation, isSource: isSelected)
                        .opacity(isSelected ? 1 : 0)
                }
                .help(tab.label)
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
