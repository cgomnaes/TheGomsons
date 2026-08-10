//
//  SubscriptionsView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: \Subscription.sortOrder) private var subscriptions: [Subscription]

    @State private var categoryFilter: SubscriptionCategoryFilter = .all
    @State private var showAdd = false
    @State private var selectedSubscription: Subscription?
    @State private var summaryPeriod: SummaryPeriod = .monthly

    enum SummaryPeriod: Int, CaseIterable {
        case monthly
        case yearly

        var title: String {
            switch self {
            case .monthly: String(localized: "subs.period.monthly")
            case .yearly: String(localized: "subs.period.yearly")
            }
        }
    }

    enum SubscriptionCategoryFilter: Int, CaseIterable {
        case all
        case streaming
        case club
        case insurance

        var title: String {
            switch self {
            case .all: String(localized: "subs.filter.all")
            case .streaming: String(localized: "subs.filter.streaming")
            case .club: String(localized: "subs.filter.clubs")
            case .insurance: String(localized: "subs.filter.insurance")
            }
        }

        func matches(_ c: SubscriptionCategory) -> Bool {
            switch self {
            case .all: true
            case .streaming: c == .streaming
            case .club: c == .clubMembership
            case .insurance: c == .travelInsurance
            }
        }
    }

    private var summaryTotal: Double {
        subscriptions
            .filter { $0.includeInSummary && $0.priceAmount > 0 && $0.billingPeriod != .oneTime }
            .reduce(0) { total, sub in
                total + (summaryPeriod == .monthly
                    ? sub.billingPeriod.toMonthly(sub.priceAmount)
                    : sub.billingPeriod.toYearly(sub.priceAmount))
            }
    }

    private var filtered: [Subscription] {
        let base = subscriptions.filter { categoryFilter.matches($0.category) }
        return base.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "subs.empty"),
                        systemImage: "creditcard.fill",
                        description: Text(String(localized: "subs.empty.detail"))
                    )
                } else {
                    List {
                        if summaryTotal > 0 {
                            Section {
                                VStack(spacing: 8) {
                                    Picker(String(localized: "subs.period"), selection: $summaryPeriod) {
                                        ForEach(SummaryPeriod.allCases, id: \.self) { p in
                                            Text(p.title).tag(p)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    Text(summaryTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                        .font(.title.weight(.bold))
                                        .monospacedDigit()
                                    Text(
                                        summaryPeriod == .monthly
                                            ? String(localized: "subs.summary_monthly_line")
                                            : String(localized: "subs.summary_yearly_line")
                                    )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                        }

                        Section {
                            Picker(String(localized: "common.category"), selection: $categoryFilter) {
                                ForEach(SubscriptionCategoryFilter.allCases, id: \.self) { f in
                                    Text(f.title).tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)

                        ForEach(filtered) { sub in
                            Button {
                                selectedSubscription = sub
                            } label: {
                                SubscriptionRowView(subscription: sub)
                            }
                        }
                        .onDelete(perform: deleteSubscriptions)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "subs.title"))
            .onAppear {
                FamilyCalendarNotifications.rescheduleAllSubExpiries(subscriptions)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "subs.add"))
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    SubscriptionEditorView(subscription: nil) {
                        showAdd = false
                    }
                }
            }
            .sheet(item: $selectedSubscription) { sub in
                NavigationStack {
                    SubscriptionDetailView(subscription: sub) {
                        selectedSubscription = nil
                    }
                }
            }
        }
    }

    private func deleteSubscriptions(at offsets: IndexSet) {
        for index in offsets {
            let sub = filtered[index]
            FamilyCalendarNotifications.cancelSubExpiry(sub)
            modelContext.delete(sub)
        }
        try? modelContext.save()
    }
}

private struct SubscriptionRowView: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            SubscriptionLogoView(subscription: subscription)
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.name.isEmpty ? String(localized: "common.untitled") : subscription.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subscription.category.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if subscription.priceAmount > 0 {
                    Text(
                        "\(subscription.priceAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")) / \(subscription.billingPeriod.displayTitle.lowercased())"
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                if let r = subscription.renewalDate {
                    Text(
                        String(
                            format: String(localized: "subs.renews_on"),
                            locale: .current,
                            r.formatted(date: .abbreviated, time: .omitted)
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let e = subscription.expiryDate {
                    Text(
                        String(
                            format: String(localized: "subs.expires_on"),
                            locale: .current,
                            e.formatted(date: .abbreviated, time: .omitted)
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(e < Date() ? .red : .orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let subscription: Subscription
    var onDone: () -> Void

    @State private var showPassword = false
    @State private var copiedPassword = false
    @State private var copiedEmail = false
    @State private var showEditor = false

    var body: some View {
        List {
            Section(String(localized: "subs.subscription")) {
                HStack(spacing: 12) {
                    SubscriptionLogoView(subscription: subscription)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscription.name.isEmpty ? String(localized: "common.untitled") : subscription.name)
                            .font(.headline)
                        Text(subscription.category.displayTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !subscription.websiteURL.isEmpty {
                Section(String(localized: "common.website")) {
                    if let url = normalizedURL {
                        Link(subscription.websiteURL, destination: url)
                    } else {
                        Text(subscription.websiteURL)
                    }
                }
            }

            if !subscription.loginEmail.isEmpty || !subscription.password.isEmpty {
                Section(String(localized: "common.login")) {
                    if !subscription.loginEmail.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "subs.email_username"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(subscription.loginEmail)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = subscription.loginEmail
                                copiedEmail = true
                            } label: {
                                Image(systemName: copiedEmail ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedEmail ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !subscription.password.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "common.password"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if showPassword {
                                    Text(subscription.password)
                                } else {
                                    Text(String(repeating: "•", count: 10))
                                }
                            }
                            Spacer()
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Button {
                                UIPasteboard.general.string = subscription.password
                                copiedPassword = true
                            } label: {
                                Image(systemName: copiedPassword ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedPassword ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if subscription.priceAmount > 0 || subscription.renewalDate != nil || subscription.expiryDate != nil {
                Section(String(localized: "common.billing")) {
                    if subscription.priceAmount > 0 {
                        HStack {
                            Text(String(localized: "common.cost"))
                            Spacer()
                            Text("\(subscription.priceAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")) / \(subscription.billingPeriod.displayTitle.lowercased())")
                                .foregroundStyle(.secondary)
                        }
                        if subscription.includeInSummary {
                            HStack {
                                Text(String(localized: "subs.in_summary"))
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    if let r = subscription.renewalDate {
                        HStack {
                            Text(String(localized: "subs.renews"))
                            Spacer()
                            Text(r, format: .dateTime.month(.abbreviated).day().year())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let e = subscription.expiryDate {
                        HStack {
                            Text(String(localized: "subs.expires"))
                            Spacer()
                            Text(e, format: .dateTime.month(.abbreviated).day().year())
                                .foregroundStyle(e < Date() ? .red : .secondary)
                        }
                    }
                }
            }

            if !subscription.notes.isEmpty {
                Section(String(localized: "common.notes")) {
                    Text(subscription.notes)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subscription.name.isEmpty ? String(localized: "subs.subscription") : subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.done")) {
                    onDone()
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "common.edit")) {
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                SubscriptionEditorView(subscription: subscription) {
                    showEditor = false
                }
            }
        }
    }

    private var normalizedURL: URL? {
        let t = subscription.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t), u.scheme != nil { return u }
        return URL(string: "https://\(t)")
    }
}

private struct SubscriptionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subscription.sortOrder) private var allSubscriptions: [Subscription]

    let subscription: Subscription?
    var onDone: () -> Void

    @State private var name = ""
    @State private var category: SubscriptionCategory = .other
    @State private var websiteURL = ""
    @State private var loginEmail = ""
    @State private var password = ""
    @State private var notes = ""
    @State private var renewalDate: Date = Date()
    @State private var hasRenewal = false
    @State private var priceAmount = ""
    @State private var billingPeriod: SubscriptionBillingPeriod = .monthly
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry = false
    @State private var includeInSummary = true
    @State private var showPassword = false
    @State private var copiedPassword = false

    private var isNew: Bool { subscription == nil }

    var body: some View {
        Form {
            Section(String(localized: "subs.subscription")) {
                HStack(alignment: .center, spacing: 12) {
                    SubscriptionLogoView(name: name, websiteURL: websiteURL, category: category)
                    TextField(String(localized: "common.name"), text: $name)
                }
                Picker(String(localized: "common.category"), selection: $category) {
                    ForEach(SubscriptionCategory.allCases, id: \.self) { c in
                        Text(c.displayTitle).tag(c)
                    }
                }
            }

            Section(String(localized: "common.website")) {
                TextField(String(localized: "subs.website_placeholder"), text: $websiteURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                if let url = normalizedURL {
                    Link(String(localized: "subs.open_browser"), destination: url)
                }
            }

            Section(String(localized: "common.login")) {
                TextField(String(localized: "subs.email_or_username"), text: $loginEmail)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                HStack {
                    if showPassword {
                        TextField(String(localized: "common.password"), text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(String(localized: "common.password"), text: $password)
                            .textContentType(.password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    if !password.isEmpty {
                        Button {
                            UIPasteboard.general.string = password
                            copiedPassword = true
                        } label: {
                            Image(systemName: copiedPassword ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedPassword ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(String(localized: "subs.stored_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "common.billing")) {
                TextField(String(localized: "subs.amount_optional"), text: $priceAmount)
                    .keyboardType(.decimalPad)
                Picker(String(localized: "subs.billing_picker"), selection: $billingPeriod) {
                    ForEach(SubscriptionBillingPeriod.allCases, id: \.self) { p in
                        Text(p.displayTitle).tag(p)
                    }
                }
                Toggle(String(localized: "subs.include_summary"), isOn: $includeInSummary)
                Toggle(String(localized: "subs.renewal_toggle"), isOn: $hasRenewal)
                if hasRenewal {
                    DatePicker(String(localized: "subs.renews"), selection: $renewalDate, displayedComponents: .date)
                }
                Toggle(String(localized: "subs.expiry_toggle"), isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker(String(localized: "subs.expires"), selection: $expiryDate, displayedComponents: .date)
                    Text(String(localized: "subs.expiry_notify"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "common.notes")) {
                TextField(String(localized: "subs.notes_hint"), text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        if let subscription {
                            FamilyCalendarNotifications.cancelSubExpiry(subscription)
                            modelContext.delete(subscription)
                            try? modelContext.save()
                        }
                        onDone()
                        dismiss()
                    } label: {
                        Text(String(localized: "common.delete"))
                    }
                }
            }
        }
        .navigationTitle(isNew ? String(localized: "subs.new_sub") : String(localized: "subs.edit_sub"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) {
                    onDone()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) {
                    save()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            guard let subscription else { return }
            name = subscription.name
            category = subscription.category
            websiteURL = subscription.websiteURL
            loginEmail = subscription.loginEmail
            password = subscription.password
            notes = subscription.notes
            if let r = subscription.renewalDate {
                renewalDate = r
                hasRenewal = true
            }
            if subscription.priceAmount > 0 {
                priceAmount = String(format: "%.2f", subscription.priceAmount)
            }
            billingPeriod = subscription.billingPeriod
            includeInSummary = subscription.includeInSummary
            if let e = subscription.expiryDate {
                expiryDate = e
                hasExpiry = true
            }
        }
    }

    private var normalizedURL: URL? {
        let t = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t), u.scheme != nil { return u }
        return URL(string: "https://\(t)")
    }

    private func save() {
        let target: Subscription
        if let subscription {
            target = subscription
        } else {
            target = Subscription()
            modelContext.insert(target)
        }

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.websiteURL = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        target.loginEmail = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        target.password = password
        target.notes = notes
        target.renewalDate = hasRenewal ? Calendar.current.startOfDay(for: renewalDate) : nil
        target.billingPeriod = billingPeriod
        target.includeInSummary = includeInSummary
        target.expiryDate = hasExpiry ? Calendar.current.startOfDay(for: expiryDate) : nil

        let trimmed = priceAmount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        target.priceAmount = Double(trimmed) ?? 0

        if isNew {
            target.sortOrder = (allSubscriptions.map(\.sortOrder).max() ?? 0) + 1
        }

        if target.expiryDate != nil {
            FamilyCalendarNotifications.scheduleSubExpiry(target)
        } else {
            FamilyCalendarNotifications.cancelSubExpiry(target)
        }

        try? modelContext.save()
        onDone()
        dismiss()
    }
}


#Preview {
    SubscriptionsView()
        .modelContainer(for: [Subscription.self], inMemory: true)
}
