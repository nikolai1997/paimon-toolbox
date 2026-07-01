import SwiftUI

struct DatabaseView: View {
    @Bindable var store: AppStore
    @State private var selectedCharacter: GameCharacter.ID?
    @State private var selectedWeapon: Weapon.ID?
    @State private var selectedMaterial: MaterialItem.ID?
    @State private var category: DatabaseCategory = .characters

    private var characters: [GameCharacter] {
        let all = store.metadata?.characters ?? []
        guard !store.searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(store.searchText) || $0.element.localizedStandardContains(store.searchText) }
    }

    private var weapons: [Weapon] {
        let all = store.metadata?.weapons ?? []
        guard !store.searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(store.searchText) || $0.type.localizedStandardContains(store.searchText) }
    }

    private var materials: [MaterialItem] {
        let all = store.metadata?.materials ?? []
        guard !store.searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(store.searchText) || $0.category.localizedStandardContains(store.searchText) || $0.source.localizedStandardContains(store.searchText) }
    }

    private var materialsByName: [String: MaterialItem] {
        (store.metadata?.materials ?? []).reduce(into: [:]) { result, item in
            result[item.name] = item
        }
    }

    private var selectedCharacterValue: GameCharacter? {
        characters.first { $0.id == selectedCharacter } ?? characters.first
    }

    private var selectedWeaponValue: Weapon? {
        weapons.first { $0.id == selectedWeapon } ?? weapons.first
    }

    private var selectedMaterialValue: MaterialItem? {
        materials.first { $0.id == selectedMaterial } ?? materials.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Picker("资料类型", selection: $category) {
                    ForEach(DatabaseCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .controlSize(.large)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .softSeparator()

            HSplitView {
                tableView
                    .padding(.top, 8)
                    .background(.thinMaterial)
                    .frame(minWidth: 520, idealWidth: 680)

                ScrollView {
                    inspectorView
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.ultraThinMaterial)
                .frame(minWidth: 300, idealWidth: 380)
            }
        }
        .background(.clear)
    }

    @ViewBuilder
    private var tableView: some View {
        switch category {
        case .characters:
            Table(characters, selection: $selectedCharacter) {
                TableColumn("名称") { character in
                    metadataNameCell(name: character.name, imageURL: character.iconURL)
                }
                TableColumn("元素", value: \.element)
                TableColumn("武器", value: \.weaponType)
                TableColumn("地区", value: \.region)
            }
        case .weapons:
            Table(weapons, selection: $selectedWeapon) {
                TableColumn("名称") { weapon in
                    metadataNameCell(name: weapon.name, imageURL: weapon.iconURL)
                }
                TableColumn("类型", value: \.type)
                TableColumn("副属性", value: \.stat)
                TableColumn("星级") { weapon in
                    Text("\(weapon.rarity)")
                }
            }
        case .materials:
            Table(materials, selection: $selectedMaterial) {
                TableColumn("名称", value: \.name)
                TableColumn("分类", value: \.category)
                TableColumn("来源", value: \.source)
            }
        }
    }

    @ViewBuilder
    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch category {
            case .characters:
                if let selectedCharacterValue {
                    characterInspector(selectedCharacterValue)
                } else {
                    emptyInspector
                }
            case .weapons:
                if let selectedWeaponValue {
                    weaponInspector(selectedWeaponValue)
                } else {
                    emptyInspector
                }
            case .materials:
                if let selectedMaterialValue {
                    materialInspector(selectedMaterialValue)
                } else {
                    emptyInspector
                }
            }
            Spacer()
        }
    }

    private func characterInspector(_ character: GameCharacter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MetadataArtworkView(
                    url: character.inspectorArtworkURL,
                    title: character.name,
                    size: 104,
                    cornerRadius: 18
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(character.name)
                        .font(.title2.bold())
                    Text("\(character.element) / \(character.weaponType)")
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await store.createCharacterPlan(for: character)
                        }
                    } label: {
                        Label("加入养成规划", systemImage: "plus.circle")
                    }
                }
            }
            LabeledContent("元素", value: character.element)
            LabeledContent("武器", value: character.weaponType)
            LabeledContent("稀有度", value: "\(character.rarity) 星")
            LabeledContent("地区", value: character.region)
            Divider()
            Text("突破材料")
                .font(.headline)
            ForEach(character.materials, id: \.self) { material in
                characterMaterialRow(name: material)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private func characterMaterialRow(name: String) -> some View {
        let item = materialsByName[name]

        return HStack(spacing: 10) {
            MetadataArtworkView(url: item?.iconURL, title: name, size: 30, cornerRadius: 8)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func weaponInspector(_ weapon: Weapon) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MetadataArtworkView(url: weapon.iconURL, title: weapon.name, size: 88, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text(weapon.name)
                        .font(.title2.bold())
                    Text("\(weapon.type) / \(weapon.stat)")
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await store.createWeaponPlan(for: weapon)
                        }
                    } label: {
                        Label("加入养成规划", systemImage: "plus.circle")
                    }
                }
            }
            LabeledContent("类型", value: weapon.type)
            LabeledContent("稀有度", value: "\(weapon.rarity) 星")
            LabeledContent("副属性", value: weapon.stat)
            Divider()
            Text("突破材料")
                .font(.headline)
            ForEach(weapon.materials, id: \.self) { material in
                Label(material, systemImage: "shippingbox")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private func materialInspector(_ material: MaterialItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                MetadataArtworkView(url: material.iconURL, title: material.name, size: 72, cornerRadius: 14)
                Text(material.name)
                    .font(.title2.bold())
            }
            LabeledContent("分类", value: material.category)
            LabeledContent("来源", value: material.source)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private var emptyInspector: some View {
        ContentUnavailableView("没有资料", systemImage: "books.vertical")
            .frame(maxWidth: .infinity, minHeight: 220)
            .glassPanel(cornerRadius: 18)
    }

    private func metadataNameCell(name: String, imageURL: URL?) -> some View {
        HStack(spacing: 8) {
            MetadataArtworkView(url: imageURL, title: name, size: 28, cornerRadius: 7)
            Text(name)
        }
    }
}

private enum DatabaseCategory: String, CaseIterable, Identifiable {
    case characters
    case weapons
    case materials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: "角色"
        case .weapons: "武器"
        case .materials: "材料"
        }
    }
}
