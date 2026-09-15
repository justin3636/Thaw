import SwiftUI

struct MenuBarItemOrderingSection: View {
    @Bindable var itemManager: MenuBarItemManager

    var body: some View {
        IceSection("Item order") {
            Toggle("Maintain item order", isOn: $itemManager.itemOrder.enabled)
            if itemManager.itemOrder.enabled {
                Picker("Thaw icon position", selection: $itemManager.itemOrder.iconPosition) {
                    Text("Left of visible items").tag(MenuBarItemOrder.IconPosition.left)
                    Text("Right of movable items").tag(MenuBarItemOrder.IconPosition.right)
                    Text("Use item order").tag(MenuBarItemOrder.IconPosition.ordered)
                }
                Text("Lower numbers appear farther left within each section. Triggers can override an item's number. The Thaw icon position takes priority.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(itemManager.itemCache.managedItems.filter { $0.isMovable }, id: \.windowID) { item in
                    LabeledContent(item.displayName) {
                        TextField("Order", value: Binding(
                            get: { itemManager.itemOrder.ranks[item.tag.tagIdentifier] ?? 1000 },
                            set: { itemManager.itemOrder.ranks[item.tag.tagIdentifier] = $0 }
                        ), format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Order for \(item.displayName)")
                    }
                }
            }
        }
        .onChange(of: itemManager.itemOrder) { _, _ in itemManager.persistItemOrder() }
    }
}
