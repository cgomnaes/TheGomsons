//
//  FamilyCalendarNotifications.swift
//  TheGomsons
//

import Foundation
import SwiftData
import UserNotifications

enum FamilyCalendarNotifications {
    private static let idPrefix = "family-event-"

    static func notificationIdentifier(for event: FamilyEvent) -> String {
        idPrefix + String(describing: event.persistentModelID)
    }

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedules one local notification before (or at) the event. Removes any previous request for this event.
    /// Birthdays use a **yearly repeating** calendar trigger; other events use a one-shot interval trigger.
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
        let id = notificationIdentifier(for: event)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        let cal = Calendar.current
        let nextCelebration = event.nextOccurrence(after: Date())
        let fireDate = cal.date(byAdding: .minute, value: -max(0, event.reminderMinutesBefore), to: nextCelebration) ?? nextCelebration
        guard fireDate > Date().addingTimeInterval(-0.5) else { return }

        let content = UNMutableNotificationContent()
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = title.isEmpty ? "Birthday" : title
        // Repeating triggers keep this text; age changes each year (refresh when you open the app).
        var body = "Annual reminder · " + nextCelebration.formatted(date: .abbreviated, time: .omitted)
        if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += " · \(event.location)"
        }
        content.body = body
        content.sound = .default

        let parts = cal.dateComponents([.month, .day, .hour, .minute], from: fireDate)
        var match = DateComponents()
        match.month = parts.month
        match.day = parts.day
        match.hour = parts.hour
        match.minute = parts.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: match, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(for event: FamilyEvent) {
        let id = notificationIdentifier(for: event)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Reschedule all future events (e.g. after CloudKit import).
    static func rescheduleAll(events: [FamilyEvent]) {
        for e in events {
            schedule(for: e)
        }
    }

    // MARK: - FamilyPerson birthday notifications (8 AM yearly)

    private static let personPrefix = "person-birthday-"

    static func notificationIdentifier(for person: FamilyPerson) -> String {
        personPrefix + String(describing: person.persistentModelID)
    }

    /// Schedule a yearly 8 AM notification on this person's birthday (month + day).
    static func schedulePersonBirthday(_ person: FamilyPerson) {
        let id = notificationIdentifier(for: person)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        guard person.includeBirthdayOnCalendar, !person.isDeceased, let birthDate = person.birthDate else { return }

        let cal = Calendar.current
        let month = cal.component(.month, from: birthDate)
        let day = cal.component(.day, from: birthDate)

        let content = UNMutableNotificationContent()
        let name = person.displayName
        content.title = "\(name.isEmpty ? "Family member" : name)'s birthday!"
        content.body = "Today is \(name.isEmpty ? "their" : name + "'s") birthday"
        content.sound = .default

        var match = DateComponents()
        match.month = month
        match.day = day
        match.hour = 8
        match.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: match, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Remove the birthday notification for a person.
    static func cancelPersonBirthday(_ person: FamilyPerson) {
        let id = notificationIdentifier(for: person)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
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
