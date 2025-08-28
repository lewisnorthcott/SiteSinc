import Foundation

struct RFIPermissions {
    // MARK: - Core helpers
    private static func permissionNames(from user: User?) -> Set<String> {
        let names = user?.permissions?.map { $0.name } ?? []
        return Set(names)
    }

    static func isManager(user: User?) -> Bool {
        let perms = permissionNames(from: user)
        return perms.contains("manage_rfis") || perms.contains("manage_any_rfis")
    }

    static func isAssigned(user: User?, to rfi: RFI) -> Bool {
        guard let userId = user?.id else { return false }
        return rfi.assignedUsers?.contains(where: { $0.user.id == userId }) == true
    }

    // MARK: - UI gating
    static func canRespond(user: User?, to rfi: RFI) -> Bool {
        let perms = permissionNames(from: user)
        let hasManageAny = perms.contains("manage_any_rfis")
        let hasRespond = perms.contains("respond_to_rfis")
        let assigned = isAssigned(user: user, to: rfi)
        return (assigned && hasRespond) || hasManageAny
    }

    static func canReview(user: User?, for rfi: RFI) -> Bool {
        let perms = permissionNames(from: user)
        let hasClose = perms.contains("close_rfis")
        let hasManageAny = perms.contains("manage_any_rfis")
        let assigned = isAssigned(user: user, to: rfi)
        return (hasClose && assigned) || hasManageAny
    }

    static func canEdit(user: User?, rfi: RFI) -> Bool {
        let perms = permissionNames(from: user)
        let assignedAndHasEdit = isAssigned(user: user, to: rfi) && perms.contains("edit_rfis")
        let isRFIManager = user?.id == rfi.managerId
        return assignedAndHasEdit || isRFIManager || isManager(user: user)
    }

    static func hasAcceptedResponse(_ rfi: RFI) -> Bool {
        if rfi.acceptedResponse != nil { return true }
        if let responses = rfi.responses {
            return responses.contains { $0.status.lowercased() == "approved" }
        }
        return false
    }

    static func shouldShowAddDrawingButton(user: User?, rfi: RFI) -> Bool {
        let statusLower = rfi.status?.lowercased() ?? ""
        if statusLower == "draft" { return canEdit(user: user, rfi: rfi) }
        let perms = permissionNames(from: user)
        return perms.contains("manage_any_rfis")
    }

    static func canClose(user: User?, rfi: RFI) -> Bool {
        let perms = permissionNames(from: user)
        let isRFIManager = user?.id == rfi.managerId
        let managerOrPerm = isRFIManager || isManager(user: user) || perms.contains("close_rfis")
        return managerOrPerm && hasAcceptedResponse(rfi)
    }

    static func canCreateRFIs(user: User?) -> Bool {
        let perms = permissionNames(from: user)
        return perms.contains("create_rfis")
    }
}




