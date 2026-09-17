//
//  FamilyCalendarNotifications.swift
//  TheGomsons
//

import Foundation
import SwiftData
import UserNotifications

enum FamilyCalendarNotifications {
    private static let idPrefix = "family-event-"
    private static let personPrefix = "person-birthday-"
    private static let todaySuffix = "-today"
    private static let tomorrowSuffix = "-tomorrow"

    /// Local notification time for annual birthdays (family tree + calendar birthday events).
    private static let birthdayNotifyHour = 8
    private static let birthdayNotifyMinute = 0

    /// Month/day/hour/minute for a yearly repeating trigger on the celebration day at 8 AM (minus optional lead time).
    private static func birthdayNotificationComponents(
        month: Int,
        day: Int,
        minutesBefore: Int = 0
    ) -> DateComponents {
        let cal = Calendar.current
        var base = DateComponents()
        base.year = cal.component(.year, from: Date())
        base.month = month
        base.day = day
        base.hour = birthdayNotifyHour
        base.minute = birthdayNotifyMinute
        guard let eightAM = cal.date(from: base) else {
            var fallback = DateComponents()
            fallback.month = month
            fallback.day = day
            fallback.hour = birthdayNotifyHour
            fallback.minute = birthdayNotifyMinute
            return fallback
        }

        let celebrationStart = cal.startOfDay(for: eightAM)
        let fireDate: Date
        if minutesBefore > 0,
           let earlier = cal.date(byAdding: .minute, value: -minutesBefore, to: eightAM),
           earlier >= celebrationStart {
            fireDate = earlier
        } else {
            fireDate = eightAM
        }

        let parts = cal.dateComponents([.month, .day, .hour, .minute], from: fireDate)
        var match = DateComponents()
        match.month = parts.month
        match.day = parts.day
        match.hour = parts.hour
        match.minute = parts.minute
        return match
    }

    /// Month/day/hour/minute for 8 AM on the calendar day before a birthday (yearly repeat).
    private static func dayBeforeBirthdayComponents(month: Int, day: Int) -> DateComponents? {
        let cal = Calendar.current
        var base = DateComponents()
        base.year = cal.component(.year, from: Date())
        base.month = month
        base.day = day
        base.hour = birthdayNotifyHour
        base.minute = birthdayNotifyMinute
        guard let birthday = cal.date(from: base),
              let dayBefore = cal.date(byAdding: .day, value: -1, to: birthday)
        else { return nil }

        let parts = cal.dateComponents([.month, .day], from: dayBefore)
        var match = DateComponents()
        match.month = parts.month
        match.day = parts.day
        match.hour = birthdayNotifyHour
        match.minute = birthdayNotifyMinute
        return match
    }

    private static func scheduleYearlyBirthdayPair(
        todayID: String,
        tomorrowID: String,
        legacyIDs: [String] = [],
        month: Int,
        day: Int,
        todayTitle: String,
        todayBody: String,
        tomorrowTitle: String,
        tomorrowBody: String,
        dayOfMinutesBefore: Int = 0
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: legacyIDs + [todayID, tomorrowID])

        guard let tomorrowMatch = dayBeforeBirthdayComponents(month: month, day: day) else { return }
        let todayMatch = birthdayNotificationComponents(
            month: month,
            day: day,
            minutesBefore: dayOfMinutesBefore
        )

        let tomorrowContent = UNMutableNotificationContent()
        tomorrowContent.title = tomorrowTitle
        tomorrowContent.body = tomorrowBody
        tomorrowContent.sound = .default
        center.add(
            UNNotificationRequest(
                identifier: tomorrowID,
                content: tomorrowContent,
                trigger: UNCalendarNotificationTrigger(dateMatching: tomorrowMatch, repeats: true)
            )
        )

        let todayContent = UNMutableNotificationContent()
        todayContent.title = todayTitle
        todayContent.body = todayBody
        todayContent.sound = .default
        center.add(
            UNNotificationRequest(
                identifier: todayID,
                content: todayContent,
                trigger: UNCalendarNotificationTrigger(dateMatching: todayMatch, repeats: true)
            )
        )
    }

    private static func displayName(for person: FamilyPerson) -> String {
        let name = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "calendar.birthday_notify.generic_name") : name
    }

    static func notificationIdentifier(for event: FamilyEvent) -> String {
        idPrefix + String(describing: event.persistentModelID)
    }

    private static func todayNotificationIdentifier(for event: FamilyEvent) -> String {
        notificationIdentifier(for: event) + todaySuffix
    }

    private static func tomorrowNotificationIdentifier(for event: FamilyEvent) -> String {
        notificationIdentifier(for: event) + tomorrowSuffix
    }

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedules one local notification before (or at) the event. Removes any previous request for this event.
    /// Birthdays use yearly repeating **today** + **tomorrow** alerts at 8 AM; other events use a one-shot interval trigger.
    static func schedule(for event: FamilyEvent) {
        if event.kind == .birthday {
            scheduleBirthday(event)
        } else {
            scheduleOneShot(event)
        }
    }

    private static func scheduleOneShot(_ event: FamilyEvent) {
        let id = notificationIdentifier(for: event)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        let fireDate = Calendar.current.date(byAdding: .minute, value: -max(0, event.reminderMinutesBefore), to: event.date) ?? event.date
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = title.isEmpty ? "Family event" : title
        var body = event.date.formatted(date: .abbreviated, time: .shortened)
        if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += " · \(event.location)"
        }
        content.body = body
        content.sound = .default

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func scheduleBirthday(_ event: FamilyEvent) {
        let cal = Calendar.current
        let nextCelebration = event.nextOccurrence(after: Date())
        let month = cal.component(.month, from: nextCelebration)
        let day = cal.component(.day, from: nextCelebration)

        let rawTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = rawTitle.isEmpty ? String(localized: "event.kind.birthday") : rawTitle

        scheduleYearlyBirthdayPair(
            todayID: todayNotificationIdentifier(for: event),
            tomorrowID: tomorrowNotificationIdentifier(for: event),
            legacyIDs: [notificationIdentifier(for: event)],
            month: month,
            day: day,
            todayTitle: label,
            todayBody: String(localized: "calendar.birthday_notify.today_body"),
            tomorrowTitle: String(
                format: String(localized: "calendar.birthday_notify.event_tomorrow_title"),
                locale: .current,
                label
            ),
            tomorrowBody: String(localized: "calendar.birthday_notify.tomorrow_body"),
            dayOfMinutesBefore: event.reminderMinutesBefore
        )
    }

    static func cancel(for event: FamilyEvent) {
        let ids = [
            notificationIdentifier(for: event),
            todayNotificationIdentifier(for: event),
            tomorrowNotificationIdentifier(for: event),
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reschedule all future events (e.g. after CloudKit import).
    static func rescheduleAll(events: [FamilyEvent]) {
        for e in events {
            schedule(for: e)
        }
    }

    // MARK: - FamilyPerson birthday notifications (8 AM day before + day of)

    static func notificationIdentifier(for person: FamilyPerson) -> String {
        personPrefix + String(describing: person.persistentModelID)
    }

    private static func todayNotificationIdentifier(for person: FamilyPerson) -> String {
        notificationIdentifier(for: person) + todaySuffix
    }

    private static func tomorrowNotificationIdentifier(for person: FamilyPerson) -> String {
        notificationIdentifier(for: person) + tomorrowSuffix
    }

    /// Schedule yearly 8 AM alerts the day before (“tomorrow”) and on the birthday (“today”).
    static func schedulePersonBirthday(_ person: FamilyPerson) {
        guard person.includeBirthdayOnCalendar, !person.isDeceased, let birthDate = person.birthDate else {
            cancelPersonBirthday(person)
            return
        }

        let cal = Calendar.current
        let month = cal.component(.month, from: birthDate)
        let day = cal.component(.day, from: birthDate)
        let name = displayName(for: person)

        scheduleYearlyBirthdayPair(
            todayID: todayNotificationIdentifier(for: person),
            tomorrowID: tomorrowNotificationIdentifier(for: person),
            legacyIDs: [notificationIdentifier(for: person)],
            month: month,
            day: day,
            todayTitle: String(
                format: String(localized: "calendar.birthday_notify.today_title"),
                locale: .current,
                name
            ),
            todayBody: String(localized: "calendar.birthday_notify.today_body"),
            tomorrowTitle: String(
                format: String(localized: "calendar.birthday_notify.tomorrow_title"),
                locale: .current,
                name
            ),
            tomorrowBody: String(localized: "calendar.birthday_notify.tomorrow_body")
        )
    }

    /// Remove the birthday notifications for a person.
    static func cancelPersonBirthday(_ person: FamilyPerson) {
        let ids = [
            notificationIdentifier(for: person),
            todayNotificationIdentifier(for: person),
            tomorrowNotificationIdentifier(for: person),
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reschedule birthday notifications for all family members who have a birth date.
    static func rescheduleAllPersonBirthdays(_ people: [FamilyPerson]) {
        for person in people {
            guard person.birthDate != nil else {
                cancelPersonBirthday(person)
                continue
            }
            if person.includeBirthdayOnCalendar && !person.isDeceased {
                schedulePersonBirthday(person)
            } else {
                cancelPersonBirthday(person)
            }
        }
    }

    // MARK: - Subscription expiry notifications (2 days before, 8 AM)

    private static let subExpiryPrefix = "sub-expiry-"

    static func expiryIdentifier(for sub: Subscription) -> String {
        subExpiryPrefix + String(describing: sub.persistentModelID)
    }

    /// Schedule a one-shot notification 2 days before a subscription's expiry date at 8 AM.
    static func scheduleSubExpiry(_ sub: Subscription) {
        let id = expiryIdentifier(for: sub)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        guard let expiry = sub.expiryDate else { return }

        let cal = Calendar.current
        guard let fireDay = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: expiry)) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = 8
        comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        let name = sub.name.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = "\(name.isEmpty ? "Subscription" : name) expiring soon"
        content.body = "Expires \(expiry.formatted(date: .abbreviated, time: .omitted)) — 2 days from now"
        content.sound = .default

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelSubExpiry(_ sub: Subscription) {
        let id = expiryIdentifier(for: sub)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func rescheduleAllSubExpiries(_ subs: [Subscription]) {
        for sub in subs where sub.expiryDate != nil {
            scheduleSubExpiry(sub)
        }
    }
}
