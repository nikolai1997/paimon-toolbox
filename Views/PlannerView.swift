import SwiftUI

struct PlannerView: View {
    @Bindable var store: AppStore
    @State private var displayMode: PlannerDisplayMode = .plans
    @State private var targetKind: PlannerTargetKind = .character
    @State private var targetSearchText = ""
    @State private var selectedCharacterID: GameCharacter.ID?
    @State private var selectedWeaponID: Weapon.ID?
    @State private var currentLevel = 1
    @State private var targetLevel = 90
    @State private var normalAttackCurrentLevel = 1
    @State private var normalAttackTargetLevel = 10
    @State private var elementalSkillCurrentLevel = 1
    @State private var elementalSkillTargetLevel = 10
    @State private var elementalBurstCurrentLevel = 1
    @State private var elementalBurstTargetLevel = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                plannerHeader
                plannerLevelControls
            }
            .padding(20)
            .glassPanel(cornerRadius: 18)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .onAppear(perform: ensureDefaultSelection)
            .onChange(of: targetKind) { _, _ in
                targetSearchText = ""
                ensureDefaultSelection()
            }
            .onChange(of: targetSearchText) { _, _ in
                syncSelectionWithFilteredTargets()
            }

            if let message = store.successMessage {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
            }

            switch displayMode {
            case .plans:
                if store.plans.isEmpty {
                    ContentUnavailableView("暂无养成计划", systemImage: "checklist", description: Text("从上方选择角色或武器后新增计划。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                } else {
                    plansGrid
                }
            case .statistics:
                let statistics = CultivationStatistics.aggregate(plans: store.plans, targetKind: "角色")
                let bossFightEstimates = CultivationStatistics.bossFightEstimates(
                    plans: store.plans,
                    characters: store.metadata?.characters ?? []
                )
                if statistics.isEmpty {
                    ContentUnavailableView("暂无角色材料统计", systemImage: "chart.bar.doc.horizontal", description: Text("添加角色养成计划后会汇总突破、天赋和等级素材。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                } else {
                    List {
                        ForEach(bossFightEstimates) { estimate in
                            bossFightEstimateView(estimate)
                                .padding(.vertical, 6)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(statistics) { item in
                            statisticView(item)
                                .padding(.vertical, 6)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(.clear)
    }

    private var plannerGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 420, maximum: 560), spacing: 16, alignment: .top)
        ]
    }

    private var plansGrid: some View {
        ScrollView {
            LazyVGrid(columns: plannerGridColumns, alignment: .leading, spacing: 16) {
                ForEach(store.plans) { plan in
                    planView(plan)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.visible)
    }

    private var plannerHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                plannerTitle
                    .frame(minWidth: 170, maxWidth: 260, alignment: .leading)

                Spacer(minLength: 12)

                plannerTargetControls
            }

            VStack(alignment: .leading, spacing: 12) {
                plannerTitle
                plannerTargetControls
            }
        }
    }

    private var plannerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("养成规划")
                .font(.largeTitle.bold())
            Text("按目标等级统计角色突破、天赋和等级素材。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var plannerTargetControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("类型", selection: $targetKind) {
                ForEach(PlannerTargetKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            TextField(searchPlaceholder, text: $targetSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            targetPicker
                .frame(width: 220)

            Button {
                Task { await createSelectedPlan() }
            } label: {
                Label("新增计划", systemImage: "plus")
            }
            .disabled(selectedTargetIsMissing)
        }
    }

    private var plannerLevelControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                levelPickers

                Spacer(minLength: 12)

                displayModePicker
            }

            VStack(alignment: .leading, spacing: 12) {
                levelPickers
                displayModePicker
            }
        }
    }

    private var levelPickers: some View {
        HStack(alignment: .top, spacing: 12) {
            levelRangePicker(title: targetKind == .character ? "角色等级" : "武器等级", current: $currentLevel, target: $targetLevel, options: levelOptions)
            if targetKind == .character {
                Divider()
                    .frame(height: 48)
                levelRangePicker(title: "普攻", current: $normalAttackCurrentLevel, target: $normalAttackTargetLevel, options: talentOptions)
                levelRangePicker(title: "战技", current: $elementalSkillCurrentLevel, target: $elementalSkillTargetLevel, options: talentOptions)
                levelRangePicker(title: "爆发", current: $elementalBurstCurrentLevel, target: $elementalBurstTargetLevel, options: talentOptions)
            }
        }
    }

    private var displayModePicker: some View {
        Picker("视图", selection: $displayMode) {
            ForEach(PlannerDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    @ViewBuilder
    private var targetPicker: some View {
        switch targetKind {
        case .character:
            Picker("目标", selection: $selectedCharacterID) {
                if filteredCharacters.isEmpty {
                    Text("没有匹配角色").tag(GameCharacter.ID?.none)
                } else {
                    Text("选择角色").tag(GameCharacter.ID?.none)
                    ForEach(filteredCharacters) { character in
                        Text(character.name).tag(Optional(character.id))
                    }
                }
            }
        case .weapon:
            Picker("目标", selection: $selectedWeaponID) {
                if filteredWeapons.isEmpty {
                    Text("没有匹配武器").tag(Weapon.ID?.none)
                } else {
                    Text("选择武器").tag(Weapon.ID?.none)
                    ForEach(filteredWeapons) { weapon in
                        Text(weapon.name).tag(Optional(weapon.id))
                    }
                }
            }
        }
    }

    private func planView(_ plan: CultivationPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MetadataArtworkView(url: plan.targetIconURL, title: plan.targetName, size: 42, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.targetName)
                        .font(.headline)
                    Text(planSubtitle(plan))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(AppFormatters.percentString(plan.completion))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    Task { await $store.wrappedValue.deletePlan(id: plan.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("删除计划")
            }
            ProgressView(value: plan.completion)
            ForEach(plan.requirements) { requirement in
                requirementRow(plan: plan, requirement: requirement)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 14)
    }

    private func requirementRow(plan: CultivationPlan, requirement: MaterialRequirement) -> some View {
        HStack(spacing: 10) {
            materialArtwork(name: requirement.materialName, size: 32, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.materialName)
                    .lineLimit(1)
                Text("剩余 \(requirement.remaining)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            TextField("拥有", value: binding(for: plan, requirement: requirement), format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 72)
            Text("/ \(requirement.required)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .leading)
            Stepper(value: binding(for: plan, requirement: requirement), in: 0...max(requirement.required, 999)) {
                EmptyView()
            }
            .labelsHidden()
            Button {
                toggleRequirementCompletion(plan: plan, requirement: requirement)
            } label: {
                Image(systemName: completionSystemImage(for: requirement))
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(completionTint(for: requirement))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(completionTint(for: requirement).opacity(0.55), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isRequirementComplete(requirement) ? "取消达成" : "标记该材料已达成")
        }
    }

    private func bossFightEstimateView(_ estimate: CultivationBossFightEstimate) -> some View {
        HStack(spacing: 12) {
            materialArtwork(name: estimate.bossMaterialName, size: 34, cornerRadius: 8, fallbackSystemImage: "scope", fallbackColor: .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("头领预计 \(estimate.estimatedFightCount) 次")
                    .font(.headline)
                Text("\(estimate.bossMaterialName) 缺 \(estimate.remainingMaterialCount) · 按每次 \(estimate.materialDropsPerFight) 个估算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 14)
    }

    private func statisticView(_ item: CultivationMaterialStatistic) -> some View {
        HStack(spacing: 12) {
            materialArtwork(
                name: item.materialName,
                size: 34,
                cornerRadius: 8,
                fallbackSystemImage: item.remaining > 0 ? "shippingbox" : "checkmark.circle",
                fallbackColor: item.remaining > 0 ? .orange : .green
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.materialName)
                    .font(.headline)
                Text("剩余 \(item.remaining)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.owned) / \(item.required)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassPanel(cornerRadius: 14)
    }

    @ViewBuilder
    private func materialArtwork(
        name: String,
        size: CGFloat,
        cornerRadius: CGFloat,
        fallbackSystemImage: String? = nil,
        fallbackColor: Color = .secondary
    ) -> some View {
        if let url = materialArtworkURL(for: name) {
            MetadataArtworkView(url: url, title: name, size: size, cornerRadius: cornerRadius)
        } else if let fallbackSystemImage {
            Image(systemName: fallbackSystemImage)
                .foregroundStyle(fallbackColor)
                .frame(width: size, height: size)
        }
    }

    private func materialArtworkURL(for materialName: String) -> URL? {
        store.metadata?.materials.first { $0.name == materialName }?.iconURL
    }

    private func binding(for plan: CultivationPlan, requirement: MaterialRequirement) -> Binding<Int> {
        Binding {
            store.plans
                .first { $0.id == plan.id }?
                .requirements
                .first { $0.id == requirement.id }?
                .owned ?? requirement.owned
        } set: { newValue in
            Task {
                await store.updateRequirement(planID: plan.id, requirementID: requirement.id, owned: newValue)
            }
        }
    }

    private func toggleRequirementCompletion(plan: CultivationPlan, requirement: MaterialRequirement) {
        let owned = isRequirementComplete(requirement)
            ? 0
            : requirement.required
        Task {
            await store.updateRequirement(planID: plan.id, requirementID: requirement.id, owned: owned)
        }
    }

    private func isRequirementComplete(_ requirement: MaterialRequirement) -> Bool {
        requirement.owned >= requirement.required
    }

    private func completionSystemImage(for requirement: MaterialRequirement) -> String {
        isRequirementComplete(requirement) ? "checkmark.square.fill" : "square"
    }

    private func completionTint(for requirement: MaterialRequirement) -> Color {
        isRequirementComplete(requirement) ? .green : .secondary
    }

    private var selectedTargetIsMissing: Bool {
        switch targetKind {
        case .character:
            return selectedCharacter == nil
        case .weapon:
            return selectedWeapon == nil
        }
    }

    private var selectedCharacter: GameCharacter? {
        guard let selectedCharacterID else { return filteredCharacters.first }
        return filteredCharacters.first { $0.id == selectedCharacterID }
    }

    private var selectedWeapon: Weapon? {
        guard let selectedWeaponID else { return filteredWeapons.first }
        return filteredWeapons.first { $0.id == selectedWeaponID }
    }

    private var filteredCharacters: [GameCharacter] {
        PlannerTargetSearch.filteredCharacters(store.metadata?.characters ?? [], query: targetSearchText)
    }

    private var filteredWeapons: [Weapon] {
        PlannerTargetSearch.filteredWeapons(store.metadata?.weapons ?? [], query: targetSearchText)
    }

    private var searchPlaceholder: String {
        switch targetKind {
        case .character: "搜索角色"
        case .weapon: "搜索武器"
        }
    }

    private func createSelectedPlan() async {
        let levelRange = currentLevel <= targetLevel
            ? (current: currentLevel, target: targetLevel)
            : (current: targetLevel, target: currentLevel)

        switch targetKind {
        case .character:
            if let selectedCharacter {
                await store.createCharacterPlan(
                    for: selectedCharacter,
                    currentLevel: levelRange.current,
                    targetLevel: levelRange.target,
                    normalAttackCurrentLevel: normalAttackCurrentLevel,
                    normalAttackTargetLevel: normalAttackTargetLevel,
                    elementalSkillCurrentLevel: elementalSkillCurrentLevel,
                    elementalSkillTargetLevel: elementalSkillTargetLevel,
                    elementalBurstCurrentLevel: elementalBurstCurrentLevel,
                    elementalBurstTargetLevel: elementalBurstTargetLevel
                )
                selectedCharacterID = selectedCharacter.id
            }
        case .weapon:
            if let selectedWeapon {
                await store.createWeaponPlan(for: selectedWeapon, currentLevel: levelRange.current, targetLevel: levelRange.target)
                selectedWeaponID = selectedWeapon.id
            }
        }
    }

    private func ensureDefaultSelection() {
        if selectedCharacterID == nil {
            selectedCharacterID = filteredCharacters.first?.id
        }
        if selectedWeaponID == nil {
            selectedWeaponID = filteredWeapons.first?.id
        }
        syncSelectionWithFilteredTargets()
    }

    private func syncSelectionWithFilteredTargets() {
        if let selectedCharacterID, !filteredCharacters.contains(where: { $0.id == selectedCharacterID }) {
            self.selectedCharacterID = filteredCharacters.first?.id
        } else if selectedCharacterID == nil {
            selectedCharacterID = filteredCharacters.first?.id
        }

        if let selectedWeaponID, !filteredWeapons.contains(where: { $0.id == selectedWeaponID }) {
            self.selectedWeaponID = filteredWeapons.first?.id
        } else if selectedWeaponID == nil {
            selectedWeaponID = filteredWeapons.first?.id
        }
    }

    private func planSubtitle(_ plan: CultivationPlan) -> String {
        var parts = ["\(plan.targetKind) \(plan.currentLevel) -> \(plan.targetLevel)"]
        if plan.targetKind == "角色",
           let normalAttackTargetLevel = plan.normalAttackTargetLevel,
           let elementalSkillTargetLevel = plan.elementalSkillTargetLevel,
           let elementalBurstTargetLevel = plan.elementalBurstTargetLevel {
            let normalAttackCurrentLevel = plan.normalAttackCurrentLevel ?? 1
            let elementalSkillCurrentLevel = plan.elementalSkillCurrentLevel ?? 1
            let elementalBurstCurrentLevel = plan.elementalBurstCurrentLevel ?? 1
            parts.append("天赋 \(normalAttackCurrentLevel)/\(elementalSkillCurrentLevel)/\(elementalBurstCurrentLevel) -> \(normalAttackTargetLevel)/\(elementalSkillTargetLevel)/\(elementalBurstTargetLevel)")
        }
        return parts.joined(separator: " · ")
    }

    private var levelOptions: [Int] {
        [1, 20, 40, 50, 60, 70, 80, 90]
    }

    private var talentOptions: [Int] {
        Array(1...10)
    }

    private func levelRangePicker(
        title: String,
        current: Binding<Int>,
        target: Binding<Int>,
        options: [Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Picker("\(title)当前", selection: current) {
                    ForEach(options, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 58)

                Text("->")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("\(title)目标", selection: target) {
                    ForEach(options, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }
        }
        .frame(width: 132, alignment: .leading)
        .onChange(of: current.wrappedValue) { _, newValue in
            if target.wrappedValue < newValue {
                target.wrappedValue = newValue
            }
        }
        .onChange(of: target.wrappedValue) { _, newValue in
            if current.wrappedValue > newValue {
                current.wrappedValue = newValue
            }
        }
    }
}

private enum PlannerDisplayMode: String, CaseIterable, Identifiable {
    case plans
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plans: "计划"
        case .statistics: "材料统计"
        }
    }
}

private enum PlannerTargetKind: String, CaseIterable, Identifiable {
    case character
    case weapon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "角色"
        case .weapon: "武器"
        }
    }
}
