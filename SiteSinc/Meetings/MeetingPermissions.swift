import Foundation

struct MeetingPermissions {
    private static func permissionNames(from user: User?) -> Set<String> {
        Set(user?.permissions?.map { $0.name } ?? [])
    }

    static func canView(user: User?) -> Bool {
        let names = permissionNames(from: user)
        return names.contains("view_meetings") || names.contains("view_all_meetings")
    }

    static func canViewAll(user: User?) -> Bool {
        permissionNames(from: user).contains("view_all_meetings")
    }

    static func canCreate(user: User?) -> Bool {
        permissionNames(from: user).contains("create_meetings")
    }

    static func canEdit(user: User?) -> Bool {
        permissionNames(from: user).contains("edit_meetings")
    }

    static func canDelete(user: User?) -> Bool {
        permissionNames(from: user).contains("delete_meetings")
    }

    static func canCloseAnyAction(user: User?) -> Bool {
        permissionNames(from: user).contains("close_any_meeting_action")
    }

    /// Assignees, meeting creator, editors, or close-any can close out an action.
    static func canCloseOut(
        user: User?,
        line: MeetingMinuteLine,
        meetingCreatedById: Int?
    ) -> Bool {
        guard let user else { return false }
        if canEdit(user: user) || canCloseAnyAction(user: user) { return true }
        if meetingCreatedById == user.id { return true }
        return line.assigneeIds.contains(user.id)
    }

    static func canReopen(user: User?, meetingCreatedById: Int?) -> Bool {
        guard let user else { return false }
        if canEdit(user: user) || canCloseAnyAction(user: user) { return true }
        return meetingCreatedById == user.id
    }
}
