import SwiftUI

/// Gentle, opt-in reminders for the three daily sets. Local only — no account, no network, no
/// entitlement beyond the notification prompt. Copy is calm: a band name and a time, never a
/// count or a streak. A denied permission is shown honestly with a link to system Settings.
struct NitnemRemindersScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors of the stored toggles so the row reflects a permission snap-back immediately.
    @State private var enabled: [NitnemBand: Bool] = [:]
    @State private var minutes: [NitnemBand: Int] = [:]
    @State private var denied = false

    private var controller: NitnemReminderController { container.reminders }

    var body: some View {
        List {
            if HukamnamaConfig.enabled { HukamnamaReminderSection() }
            if denied {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Reminders are turned off for Gurbani Soul in iOS Settings.")
                            .font(.subheadline)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .inkRow()
            }
            Section {
                ForEach(NitnemReminders.bands, id: \.self) { band in
                    reminderRow(band)
                }
            } footer: {
                Text("A quiet nudge at a time you choose. Everything stays on this device — no account, no network. Turn a reminder off any time.")
            }
            .inkRow()
        }
        .inkGroupedList()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshState() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshState() } } }
    }

    @ViewBuilder private func reminderRow(_ band: NitnemBand) -> some View {
        let isOn = Binding(
            get: { enabled[band] ?? false },
            set: { want in
                enabled[band] = want   // optimistic; the async result corrects a denial
                Task {
                    let settled = await controller.setEnabled(want, band: band,
                                                              completedToday: await container.completedReminderBands())
                    enabled[band] = settled
                    if want && !settled { denied = true }
                }
            }
        )
        let time = Binding<Date>(
            get: { dateFor(minutes[band] ?? NitnemReminders.defaultMinute(band)) },
            set: { newDate in
                let m = minuteOfDay(newDate)
                minutes[band] = m
                UserDefaults.standard.set(m, forKey: NitnemReminderController.minuteKey(band))
                Task { await container.refreshReminders() }
            }
        )
        Toggle(NitnemReminders.copy(band).title, isOn: isOn)
            .accessibilityIdentifier("reminder_\(band.rawValue)")
        if enabled[band] == true {
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("reminderTime_\(band.rawValue)")
        }
    }

    private func refreshState() async {
        for band in NitnemReminders.bands {
            enabled[band] = controller.isEnabled(band)
            minutes[band] = controller.minute(band)
        }
        denied = await controller.authStatusIsDenied()
    }

    private func dateFor(_ minute: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }
    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// The Hukamnama from Sri Harmandir Sahib: the opt-in push, at the top of Reminders. Unlike the
/// Nitnem reminders this one uses the network — the footer says so plainly. The permission prompt
/// is shown only from this toggle.
struct HukamnamaReminderSection: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    /// Mirrors the controller so the toggle moves at once; the async result corrects it.
    @State private var on = false

    static let header = "Hukamnama from Sri Harmandir Sahib"
    static let toggle = "Daily Hukamnama"
    static let asap = "As soon as it's published"
    static let atTime = "At a time I choose"
    static let footer = "The Hukamnama is located each morning from SGPC and its text comes from Sri Guru Granth Sahib Ji in this app. When this is on, this device's notification token and your chosen time are sent to Algorythmos to deliver it. Turning it off deletes them."

    private var push: HukamnamaPushController { container.hukamnamaPush }

    var body: some View {
        Section {
            Toggle(Self.toggle, isOn: Binding(
                get: { on },
                set: { want in
                    on = want
                    Task { on = await push.setEnabled(want) }
                }))
                .disabled(push.busy)
                .accessibilityIdentifier("hukamnamaToggle")
            if let message = push.message {
                Text(message).font(.footnote).foregroundStyle(Ink.negative)
                    .accessibilityIdentifier("hukamnamaMessage")
            }
            if push.denied {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Notifications are turned off for Gurbani Soul in iOS Settings.").font(.subheadline)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url).font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityIdentifier("hukamnamaDenied")
            }
            if on {
                Picker("Deliver", selection: Binding(get: { push.mode }, set: { push.setMode($0) })) {
                    Text(Self.asap).tag(HukamnamaMode.asap)
                    Text(Self.atTime).tag(HukamnamaMode.scheduled)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("hukamnamaMode")
                if push.mode == .asap {
                    Text("Usually around \(HukamnamaSchedule.usualLocalTime(now: Date())) your time")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("hukamnamaEstimate")
                } else {
                    DatePicker("Time", selection: Binding(
                        get: { Self.date(for: push.minute) },
                        set: { push.setMinute(Self.minuteOfDay($0)) }),
                               displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("hukamnamaTime")
                    Text(HukamnamaDeliveryCopy.lateNote)
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("hukamnamaLateNote")
                }
                if let line = HukamnamaDeliveryCopy.line(
                    status: push.deliveryStatus, receivedAt: push.deliveryStatusAt, mode: push.mode,
                    settingsChangedAt: push.settingsChangedAt, changePending: push.changePending,
                    now: Date(), locale: locale) {
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("hukamnamaDeliveryStatus")
                }
            }
            #if DEBUG
            if DebugHooks.isUITest {
                Text(push.debugSummary).font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityIdentifier("hukamnamaDebugState")
            }
            #endif
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
        .inkRow()
        .task { on = push.wanted; await push.refresh(); on = push.wanted }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await push.refresh(); on = push.wanted } }
        }
    }

    static func date(for minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }
    static func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
