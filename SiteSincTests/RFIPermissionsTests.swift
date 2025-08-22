import XCTest
@testable import SiteSinc

final class RFIPermissionsTests: XCTestCase {
    private func makeUser(id: Int = 1, permissions: [String]) -> User {
        let perms = permissions.enumerated().map { index, name in Permission(id: index + 1, name: name) }
        return User(
            id: id,
            firstName: "Test",
            lastName: "User",
            email: "test@example.com",
            tenantId: 1,
            companyId: nil,
            company: nil,
            roles: nil,
            permissions: perms,
            projectPermissions: nil,
            isSubscriptionOwner: nil,
            assignedProjects: nil,
            assignedSubcontractOrders: nil,
            blocked: nil,
            createdAt: nil,
            userRoles: nil,
            userPermissions: nil,
            tenants: nil
        )
    }

    private func makeRFI(
        managerId: Int? = nil,
        assignedUserIds: [Int] = [],
        status: String = "submitted",
        responses: [RFI.RFIResponseItem]? = nil,
        acceptedResponse: RFI.RFIResponseItem? = nil
    ) -> RFI {
        let assignedUsers = assignedUserIds.map { userId in
            RFI.AssignedUser(user: .init(id: userId, firstName: "U\(userId)", lastName: "L\(userId)"))
        }
        return RFI(
            id: 100,
            number: 1,
            title: "Test",
            description: nil,
            query: nil,
            status: status,
            createdAt: nil,
            submittedDate: nil,
            returnDate: nil,
            closedDate: nil,
            projectId: 10,
            submittedBy: nil,
            managerId: managerId,
            manager: nil,
            assignedUsers: assignedUsers,
            attachments: nil,
            drawings: nil,
            responses: responses,
            acceptedResponse: acceptedResponse
        )
    }

    func testCanRespond_AssignedWithPermission() {
        let user = makeUser(permissions: ["respond_to_rfis"]) // id 1 by default
        let rfi = makeRFI(assignedUserIds: [1])
        XCTAssertTrue(RFIPermissions.canRespond(user: user, to: rfi))
    }

    func testCanRespond_NotAssignedButManager() {
        let user = makeUser(permissions: ["manage_rfis"]) // manager permission
        let rfi = makeRFI(assignedUserIds: [2])
        XCTAssertTrue(RFIPermissions.canRespond(user: user, to: rfi))
    }

    func testCanRespond_AssignedWithoutPermission() {
        let user = makeUser(permissions: [])
        let rfi = makeRFI(assignedUserIds: [1])
        XCTAssertFalse(RFIPermissions.canRespond(user: user, to: rfi))
    }

    func testCanReview_ManagerOfRFI() {
        let user = makeUser(id: 5, permissions: [])
        let rfi = makeRFI(managerId: 5)
        XCTAssertTrue(RFIPermissions.canReview(user: user, for: rfi))
    }

    func testCanReview_WithManagePermission() {
        let user = makeUser(permissions: ["manage_any_rfis"])
        let rfi = makeRFI(managerId: 99)
        XCTAssertTrue(RFIPermissions.canReview(user: user, for: rfi))
    }

    func testCanEdit_AssignedWithEditPermission() {
        let user = makeUser(permissions: ["edit_rfis"]) // id 1
        let rfi = makeRFI(managerId: 2, assignedUserIds: [1])
        XCTAssertTrue(RFIPermissions.canEdit(user: user, rfi: rfi))
    }

    func testCanEdit_ManagerOrManagePerm() {
        let managerUser = makeUser(id: 7, permissions: [])
        let rfi1 = makeRFI(managerId: 7, assignedUserIds: [1])
        XCTAssertTrue(RFIPermissions.canEdit(user: managerUser, rfi: rfi1))

        let manageUser = makeUser(id: 8, permissions: ["manage_rfis"])
        let rfi2 = makeRFI(managerId: 9)
        XCTAssertTrue(RFIPermissions.canEdit(user: manageUser, rfi: rfi2))
    }

    func testHasAcceptedResponse() {
        let user = RFI.UserInfo(id: 2, firstName: "A", lastName: "B")
        let approved = RFI.RFIResponseItem(id: 1, content: "", createdAt: "", updatedAt: nil, status: "approved", rejectionReason: nil, user: user, attachments: nil)
        let pending = RFI.RFIResponseItem(id: 2, content: "", createdAt: "", updatedAt: nil, status: "pending", rejectionReason: nil, user: user, attachments: nil)
        let rfi = makeRFI(responses: [pending, approved], acceptedResponse: nil)
        XCTAssertTrue(RFIPermissions.hasAcceptedResponse(rfi))
    }

    func testShouldShowAddDrawingButton_DraftUsesEdit() {
        let user = makeUser(permissions: ["edit_rfis"]) // id 1
        let draft = makeRFI(assignedUserIds: [1], status: "draft")
        XCTAssertTrue(RFIPermissions.shouldShowAddDrawingButton(user: user, rfi: draft))
    }

    func testShouldShowAddDrawingButton_SubmittedNeedsManageAny() {
        let user = makeUser(permissions: ["manage_rfis"]) // not manage_any_rfis
        let rfi = makeRFI(status: "submitted")
        XCTAssertFalse(RFIPermissions.shouldShowAddDrawingButton(user: user, rfi: rfi))

        let user2 = makeUser(permissions: ["manage_any_rfis"]) // allowed
        XCTAssertTrue(RFIPermissions.shouldShowAddDrawingButton(user: user2, rfi: rfi))
    }

    func testCanClose_NeedsAcceptedResponseAndManagerOrPermission() {
        let userInfo = RFI.UserInfo(id: 3, firstName: "A", lastName: "B")
        let approved = RFI.RFIResponseItem(id: 1, content: "", createdAt: "", updatedAt: nil, status: "approved", rejectionReason: nil, user: userInfo, attachments: nil)
        let rfiAccepted = makeRFI(managerId: 9, responses: [approved], acceptedResponse: approved)

        let noPermUser = makeUser(id: 1, permissions: [])
        XCTAssertFalse(RFIPermissions.canClose(user: noPermUser, rfi: rfiAccepted))

        let managerUser = makeUser(id: 9, permissions: [])
        XCTAssertTrue(RFIPermissions.canClose(user: managerUser, rfi: rfiAccepted))

        let closePermUser = makeUser(id: 2, permissions: ["close_rfis"]) 
        XCTAssertTrue(RFIPermissions.canClose(user: closePermUser, rfi: rfiAccepted))
    }

    func testCanCreateRFIs() {
        XCTAssertTrue(RFIPermissions.canCreateRFIs(user: makeUser(permissions: ["create_rfis"])))
        XCTAssertFalse(RFIPermissions.canCreateRFIs(user: makeUser(permissions: [])))
    }
}




