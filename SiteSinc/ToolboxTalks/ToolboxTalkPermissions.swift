import Foundation

struct ToolboxTalkPermissions {
    private static func permissionNames(from user: User?) -> Set<String> {
        Set(user?.permissions?.map { $0.name } ?? [])
    }

    static func canView(user: User?) -> Bool {
        permissionNames(from: user).contains("view_toolbox_talks")
    }

    static func canAssign(user: User?) -> Bool {
        permissionNames(from: user).contains("assign_toolbox_talk_to_project")
    }

    static func canAmend(user: User?) -> Bool {
        permissionNames(from: user).contains("amend_project_toolbox_talk")
    }

    static func canSchedule(user: User?) -> Bool {
        permissionNames(from: user).contains("schedule_toolbox_talk_sessions")
    }

    static func canDeliver(user: User?) -> Bool {
        permissionNames(from: user).contains("deliver_toolbox_talk_sessions")
    }

    static func canManageAttendees(user: User?) -> Bool {
        permissionNames(from: user).contains("manage_toolbox_talk_attendees")
    }

    static func canProxySign(user: User?) -> Bool {
        canDeliver(user: user) || canManageAttendees(user: user)
    }

    static func canGenerateAI(user: User?) -> Bool {
        permissionNames(from: user).contains("edit_toolbox_talk_templates")
    }

    static func canArchive(user: User?) -> Bool {
        permissionNames(from: user).contains("archive_toolbox_talks")
    }
}
