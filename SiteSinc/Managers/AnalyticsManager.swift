import Foundation
import SwiftUI
import FirebaseAnalytics

/// Google Analytics 4 (GA4) Analytics Manager for iOS
/// Mirrors the frontend analytics.ts implementation for consistency across platforms
/// 
/// Uses Firebase Analytics to send events to Google Analytics
/// 
/// Setup:
/// 1. Add GoogleService-Info.plist to your project
/// 2. Initialize Firebase in AppDelegate
/// 3. Events will be sent automatically via Firebase

final class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()
    
    /// Debug mode logs events to console in addition to sending to GA4
    var debugMode: Bool = false
    
    #if DEBUG
    private var isDebugEnabled = true
    #else
    private var isDebugEnabled = false
    #endif
    
    // MARK: - GA4 Configuration
    
    /// GA4 Measurement ID - Get from Google Analytics Admin → Data Streams
    /// Format: G-XXXXXXXXXX
    /// Can be set in Info.plist as "GA_MEASUREMENT_ID" or override here
    private var measurementID: String? {
        // First check Info.plist
        if let plistID = Bundle.main.infoDictionary?["GA_MEASUREMENT_ID"] as? String, !plistID.isEmpty {
            return plistID
        }
        // Or set directly here (remove after adding to Info.plist)
        // return "G-XXXXXXXXXX"
        return nil
    }
    
    /// GA4 API Secret - Get from GA4 Admin → Data Streams → Measurement Protocol API secrets
    /// Optional but recommended for production
    private var apiSecret: String? {
        if let secret = Bundle.main.infoDictionary?["GA_API_SECRET"] as? String, !secret.isEmpty {
            return secret
        }
        return nil
    }
    
    /// GA4 Measurement Protocol endpoint
    private var measurementEndpoint: String {
        guard let measurementID = measurementID else {
            return ""
        }
        if let apiSecret = apiSecret, !apiSecret.isEmpty {
            // Use API secret endpoint (recommended for production)
            // URL encode the API secret to handle special characters
            let encodedSecret = apiSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiSecret
            return "https://www.google-analytics.com/mp/collect?measurement_id=\(measurementID)&api_secret=\(encodedSecret)"
        } else {
            // Use debug endpoint for testing (validates but doesn't store data)
            // NOTE: For production, you MUST add an API secret!
            if isDebugEnabled || debugMode {
                print("⚠️ [Analytics] No API secret configured. Using debug endpoint (events won't be stored).")
                print("⚠️ [Analytics] Add GA_API_SECRET to Info.plist for production tracking.")
            }
            return "https://www.google-analytics.com/debug/mp/collect?measurement_id=\(measurementID)"
        }
    }
    
    /// Client ID - unique identifier for this app installation
    private var clientID: String {
        let key = "GA4_ClientID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        // Generate new client ID (UUID format)
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
    
    /// User ID (set after login)
    private var userID: String?
    
    private init() {}
    
    // MARK: - GA4 Event Names (matching frontend)
    
    enum EventName: String {
        // Engagement events
        case pageView = "page_view"
        case screenView = "screen_view"
        case scroll = "scroll"
        case fileDownload = "file_download"
        
        // Navigation events
        case navClick = "navigation_click"
        
        // Form events
        case formStart = "form_start"
        case formSubmit = "form_submit"
        case formError = "form_error"
        case formComplete = "form_complete"
        
        // Conversion events
        case signUp = "sign_up"
        case login = "login"
        case logout = "logout"
        
        // Feature events
        case featureSearch = "feature_search"
        case featureFilter = "feature_filter"
        case featureExport = "export"
        case featureTabSwitch = "feature_tab_switch"
        
        // Project events
        case projectView = "project_view"
        case projectCreate = "project_create"
        case projectEdit = "project_edit"
        
        // RFI events
        case rfiCreate = "rfi_create"
        case rfiView = "rfi_view"
        case rfiResponse = "rfi_response"
        case rfiStatusChange = "rfi_status_change"
        
        // Drawing events
        case drawingUpload = "drawing_upload"
        case drawingView = "drawing_view"
        case drawingDownload = "drawing_download"
        
        // Document events
        case documentUpload = "document_upload"
        case documentView = "document_view"
        case documentDownload = "document_download"
        
        // Form submission events
        case formSubmission = "form_submission"
        case formTemplateCreate = "form_create"
        
        // Photo events
        case photoUpload = "photo_upload"
        case photoView = "photo_view"
        
        // Log events
        case logCreate = "daily_diary_create"
        case logView = "daily_diary_view"
        
        // Material Requisition events
        case materialRequisitionCreate = "material_requisition_create"
        case materialRequisitionStatusChange = "material_requisition_status_change"
        
        // Inspection events
        case inspectionCreate = "inspection_create"
        case inspectionComplete = "inspection_complete"
        case inspectionView = "inspection_view"
        
        // Snag events
        case snagCreate = "snag_create"
        case snagView = "snag_view"
        case snagStatusChange = "snag_status_change"
        
        // Chat events
        case chatMessageSend = "chat_message_send"
        case chatView = "chat_view"
    }
    
    // MARK: - Core Tracking Methods
    
    /// Track a custom event with parameters
    /// - Parameters:
    ///   - eventName: The GA4 event name
    ///   - parameters: Dictionary of event parameters
    func trackEvent(_ eventName: EventName, parameters: [String: Any]? = nil) {
        trackEvent(eventName.rawValue, parameters: parameters)
    }
    
    /// Track a custom event with a string event name
    /// - Parameters:
    ///   - eventName: The event name string
    ///   - parameters: Dictionary of event parameters
    func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]
        
        // Add platform identifier
        params["platform"] = "ios"
        params["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        if isDebugEnabled || debugMode {
            print("📊 [Analytics] Event: \(eventName), Parameters: \(params)")
        }
        
        // Convert parameters to [String: Any] format for Firebase
        var firebaseParams: [String: Any] = [:]
        for (key, value) in params {
            firebaseParams[key] = value
        }
        
        // Send to Firebase Analytics
        Analytics.logEvent(eventName, parameters: firebaseParams)
        
        if isDebugEnabled || debugMode {
            print("✅ [Analytics] Event sent via Firebase: \(eventName)")
        }
    }
    
    // MARK: - GA4 Measurement Protocol
    
    /// Send event to GA4 using Measurement Protocol
    private func sendToGA4(eventName: String, parameters: [String: Any], measurementID: String) {
        guard !measurementEndpoint.isEmpty, let url = URL(string: measurementEndpoint) else {
            if isDebugEnabled || debugMode {
                print("❌ [Analytics] Invalid measurement endpoint")
            }
            return
        }
        
        // Convert parameters to GA4 format (only string/number/bool values)
        var eventParams: [String: Any] = [:]
        for (key, value) in parameters {
            // GA4 only accepts string, number, or boolean
            if let str = value as? String {
                eventParams[key] = str
            } else if let num = value as? NSNumber {
                eventParams[key] = num
            } else if let bool = value as? Bool {
                eventParams[key] = bool
            } else if let int = value as? Int {
                eventParams[key] = int
            } else if let double = value as? Double {
                eventParams[key] = double
            } else {
                // Convert other types to string
                eventParams[key] = String(describing: value)
            }
        }
        
        // Build the payload - events should be an array of event objects
        var payload: [String: Any] = [
            "client_id": clientID,
            "events": [
                [
                    "name": eventName,
                    "params": eventParams
                ]
            ]
        ]
        
        // Add user_id if set
        if let userID = userID {
            payload["user_id"] = userID
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            if isDebugEnabled || debugMode {
                print("❌ [Analytics] Failed to serialize payload: \(error)")
            }
            return
        }
        
        // Log the request for debugging
        if isDebugEnabled || debugMode {
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📤 [Analytics] Sending to GA4:")
                print("📤 [Analytics] URL: \(url.absoluteString)")
                print("📤 [Analytics] Payload:\n\(jsonString)")
            }
        }
        
        // Send asynchronously (fire and forget)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if self.isDebugEnabled || self.debugMode {
                    print("❌ [Analytics] Network error: \(error.localizedDescription)")
                    print("❌ [Analytics] URL: \(url.absoluteString)")
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    if self.isDebugEnabled || self.debugMode {
                        print("✅ [Analytics] Event sent successfully: \(eventName) (Status: \(httpResponse.statusCode))")
                    }
                } else {
                    // Log error response body for debugging
                    var errorBody = ""
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        errorBody = body
                    }
                    if self.isDebugEnabled || self.debugMode {
                        print("⚠️ [Analytics] GA4 returned status: \(httpResponse.statusCode)")
                        if !errorBody.isEmpty {
                            print("⚠️ [Analytics] Error response: \(errorBody)")
                        }
                        print("⚠️ [Analytics] URL: \(url.absoluteString)")
                    }
                }
            } else {
                if self.isDebugEnabled || self.debugMode {
                    print("⚠️ [Analytics] No HTTP response received")
                }
            }
        }.resume()
    }
    
    // MARK: - Screen View Tracking
    
    /// Track a screen view (equivalent to page_view in web)
    /// - Parameters:
    ///   - screenName: The name of the screen
    ///   - screenClass: The class name of the screen (optional)
    ///   - projectId: Associated project ID if applicable
    func trackScreenView(_ screenName: String, screenClass: String? = nil, projectId: Int? = nil) {
        // Build parameters for screen_view event
        var params: [String: Any] = [
            "screen_name": screenName,
            "screen_class": screenClass ?? screenName.replacingOccurrences(of: " ", with: "")
        ]
        
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        
        // Send screen_view event (Firebase Analytics automatically tracks this as a screen view)
        trackEvent(.screenView, parameters: params)
        
        if isDebugEnabled || debugMode {
            print("📱 [Analytics] Screen view: \(screenName)")
        }
    }
    
    // MARK: - Authentication Events
    
    /// Track user login
    /// - Parameter method: Login method (e.g., "email", "sso")
    func trackLogin(method: String = "email") {
        trackEvent(.login, parameters: [
            "method": method
        ])
    }
    
    /// Track user logout
    func trackLogout() {
        trackEvent(.logout)
    }
    
    // MARK: - Project Events
    
    /// Track project view
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - projectName: The project name (optional)
    func trackProjectView(projectId: Int, projectName: String? = nil) {
        var params: [String: Any] = [
            "project_id": String(projectId)
        ]
        if let name = projectName {
            params["project_name"] = name
        }
        trackEvent(.projectView, parameters: params)
    }
    
    // MARK: - RFI Events
    
    /// Track RFI creation
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - hasAttachments: Whether the RFI has attachments
    func trackRFICreate(projectId: Int, hasAttachments: Bool = false) {
        trackEvent(.rfiCreate, parameters: [
            "project_id": String(projectId),
            "has_attachments": hasAttachments
        ])
    }
    
    /// Track RFI view
    /// - Parameters:
    ///   - rfiId: The RFI ID
    ///   - projectId: The project ID (optional)
    func trackRFIView(rfiId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "rfi_id": String(rfiId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.rfiView, parameters: params)
    }
    
    /// Track RFI response submission
    /// - Parameters:
    ///   - rfiId: The RFI ID
    ///   - projectId: The project ID (optional)
    func trackRFIResponse(rfiId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "rfi_id": String(rfiId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.rfiResponse, parameters: params)
    }
    
    /// Track RFI status change
    /// - Parameters:
    ///   - rfiId: The RFI ID
    ///   - oldStatus: Previous status
    ///   - newStatus: New status
    ///   - projectId: The project ID (optional)
    func trackRFIStatusChange(rfiId: Int, oldStatus: String, newStatus: String, projectId: Int? = nil) {
        var params: [String: Any] = [
            "rfi_id": String(rfiId),
            "old_status": oldStatus,
            "new_status": newStatus
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.rfiStatusChange, parameters: params)
    }
    
    // MARK: - Drawing Events
    
    /// Track drawing upload
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - fileCount: Number of files uploaded
    ///   - totalSizeMB: Total size in MB (optional)
    func trackDrawingUpload(projectId: Int, fileCount: Int, totalSizeMB: Double? = nil) {
        var params: [String: Any] = [
            "project_id": String(projectId),
            "file_count": fileCount
        ]
        if let size = totalSizeMB {
            params["total_size_mb"] = size
        }
        trackEvent(.drawingUpload, parameters: params)
    }
    
    /// Track drawing view
    /// - Parameters:
    ///   - drawingId: The drawing ID
    ///   - projectId: The project ID (optional)
    ///   - fileType: The file type (optional)
    func trackDrawingView(drawingId: Int, projectId: Int? = nil, fileType: String? = nil) {
        var params: [String: Any] = [
            "drawing_id": String(drawingId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        if let fileType = fileType {
            params["file_type"] = fileType
        }
        trackEvent(.drawingView, parameters: params)
    }
    
    /// Track drawing download
    /// - Parameters:
    ///   - drawingId: The drawing ID
    ///   - projectId: The project ID (optional)
    func trackDrawingDownload(drawingId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "file_id": String(drawingId),
            "file_type": "drawing"
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.fileDownload, parameters: params)
    }
    
    // MARK: - Document Events
    
    /// Track document upload
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - fileCount: Number of files uploaded
    ///   - folderPath: The folder path (optional)
    func trackDocumentUpload(projectId: Int, fileCount: Int, folderPath: String? = nil) {
        var params: [String: Any] = [
            "project_id": String(projectId),
            "file_count": fileCount
        ]
        if let path = folderPath {
            params["folder_path"] = path
        }
        trackEvent(.documentUpload, parameters: params)
    }
    
    /// Track document view
    /// - Parameters:
    ///   - documentId: The document ID
    ///   - projectId: The project ID (optional)
    func trackDocumentView(documentId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "document_id": String(documentId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.documentView, parameters: params)
    }
    
    /// Track document download
    /// - Parameters:
    ///   - documentId: The document ID
    ///   - projectId: The project ID (optional)
    func trackDocumentDownload(documentId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "file_id": String(documentId),
            "file_type": "document"
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.fileDownload, parameters: params)
    }
    
    // MARK: - Form Events
    
    /// Track form submission creation
    /// - Parameters:
    ///   - formId: The form ID
    ///   - formName: The form name (optional)
    ///   - projectId: The project ID (optional)
    ///   - fieldCount: Number of fields (optional)
    func trackFormSubmission(formId: Int, formName: String? = nil, projectId: Int? = nil, fieldCount: Int? = nil) {
        var params: [String: Any] = [
            "form_id": String(formId)
        ]
        if let name = formName {
            params["form_name"] = name
        }
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        if let count = fieldCount {
            params["field_count"] = count
        }
        trackEvent(.formSubmission, parameters: params)
    }
    
    // MARK: - Photo Events
    
    /// Track photo upload
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - photoCount: Number of photos uploaded
    ///   - hasLocation: Whether photos have location data
    func trackPhotoUpload(projectId: Int, photoCount: Int, hasLocation: Bool = false) {
        trackEvent(.photoUpload, parameters: [
            "project_id": String(projectId),
            "photo_count": photoCount,
            "has_location": hasLocation
        ])
    }
    
    /// Track photo view
    /// - Parameters:
    ///   - photoId: The photo ID
    ///   - projectId: The project ID (optional)
    func trackPhotoView(photoId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "photo_id": String(photoId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.photoView, parameters: params)
    }
    
    // MARK: - Log Events (Daily Diary)
    
    /// Track log/diary creation
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - hasWeather: Whether log has weather data
    ///   - hasOperatives: Whether log has operatives data
    func trackLogCreate(projectId: Int, hasWeather: Bool = false, hasOperatives: Bool = false) {
        trackEvent(.logCreate, parameters: [
            "project_id": String(projectId),
            "has_weather": hasWeather,
            "has_operatives": hasOperatives
        ])
    }
    
    /// Track log view
    /// - Parameters:
    ///   - logId: The log ID
    ///   - projectId: The project ID (optional)
    func trackLogView(logId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "diary_id": String(logId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.logView, parameters: params)
    }
    
    // MARK: - Material Requisition Events
    
    /// Track material requisition creation
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - itemCount: Number of items (optional)
    func trackMaterialRequisitionCreate(projectId: Int, itemCount: Int? = nil) {
        var params: [String: Any] = [
            "project_id": String(projectId)
        ]
        if let count = itemCount {
            params["item_count"] = count
        }
        trackEvent(.materialRequisitionCreate, parameters: params)
    }
    
    /// Track material requisition status change
    /// - Parameters:
    ///   - requisitionId: The requisition ID
    ///   - oldStatus: Previous status
    ///   - newStatus: New status
    ///   - projectId: The project ID (optional)
    func trackMaterialRequisitionStatusChange(requisitionId: Int, oldStatus: String, newStatus: String, projectId: Int? = nil) {
        var params: [String: Any] = [
            "requisition_id": String(requisitionId),
            "old_status": oldStatus,
            "new_status": newStatus
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.materialRequisitionStatusChange, parameters: params)
    }
    
    // MARK: - Inspection Events
    
    /// Track inspection creation
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - templateId: The template ID (optional)
    ///   - templateName: The template name (optional)
    func trackInspectionCreate(projectId: Int, templateId: Int? = nil, templateName: String? = nil) {
        var params: [String: Any] = [
            "project_id": String(projectId)
        ]
        if let templateId = templateId {
            params["template_id"] = String(templateId)
        }
        if let name = templateName {
            params["template_name"] = name
        }
        trackEvent(.inspectionCreate, parameters: params)
    }
    
    /// Track inspection completion
    /// - Parameters:
    ///   - inspectionId: The inspection ID
    ///   - projectId: The project ID (optional)
    ///   - defectCount: Number of defects found (optional)
    func trackInspectionComplete(inspectionId: Int, projectId: Int? = nil, defectCount: Int? = nil) {
        var params: [String: Any] = [
            "inspection_id": String(inspectionId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        if let count = defectCount {
            params["defect_count"] = count
        }
        trackEvent(.inspectionComplete, parameters: params)
    }
    
    /// Track inspection view
    /// - Parameters:
    ///   - inspectionId: The inspection ID
    ///   - projectId: The project ID (optional)
    func trackInspectionView(inspectionId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "inspection_id": String(inspectionId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.inspectionView, parameters: params)
    }
    
    // MARK: - Snag Events
    
    /// Track snag creation
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - hasPhotos: Whether snag has photos
    func trackSnagCreate(projectId: Int, hasPhotos: Bool = false) {
        trackEvent(.snagCreate, parameters: [
            "project_id": String(projectId),
            "has_photos": hasPhotos
        ])
    }
    
    /// Track snag view
    /// - Parameters:
    ///   - snagId: The snag ID
    ///   - projectId: The project ID (optional)
    func trackSnagView(snagId: Int, projectId: Int? = nil) {
        var params: [String: Any] = [
            "snag_id": String(snagId)
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.snagView, parameters: params)
    }
    
    // MARK: - Search & Filter Events
    
    /// Track feature search
    /// - Parameters:
    ///   - feature: The feature name (e.g., "rfi", "drawings")
    ///   - query: The search query
    ///   - resultCount: Number of results (optional)
    ///   - projectId: The project ID (optional)
    func trackFeatureSearch(feature: String, query: String, resultCount: Int? = nil, projectId: Int? = nil) {
        var params: [String: Any] = [
            "feature": feature,
            "search_term": query
        ]
        if let count = resultCount {
            params["search_results_count"] = count
        }
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.featureSearch, parameters: params)
    }
    
    /// Track feature filter
    /// - Parameters:
    ///   - feature: The feature name
    ///   - filterType: The type of filter
    ///   - filterValue: The filter value
    ///   - projectId: The project ID (optional)
    func trackFeatureFilter(feature: String, filterType: String, filterValue: String, projectId: Int? = nil) {
        var params: [String: Any] = [
            "feature": feature,
            "filter_type": filterType,
            "filter_value": filterValue
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.featureFilter, parameters: params)
    }
    
    // MARK: - Export Events
    
    /// Track export action
    /// - Parameters:
    ///   - feature: The feature being exported
    ///   - format: The export format (e.g., "pdf", "excel")
    ///   - projectId: The project ID (optional)
    ///   - itemCount: Number of items exported (optional)
    func trackExport(feature: String, format: String, projectId: Int? = nil, itemCount: Int? = nil) {
        var params: [String: Any] = [
            "feature": feature,
            "export_format": format
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        if let count = itemCount {
            params["item_count"] = count
        }
        trackEvent(.featureExport, parameters: params)
    }
    
    // MARK: - Navigation Events
    
    /// Track navigation click
    /// - Parameters:
    ///   - destination: The navigation destination
    ///   - linkText: The text of the link (optional)
    func trackNavigation(destination: String, linkText: String? = nil) {
        var params: [String: Any] = [
            "navigation_destination": destination
        ]
        if let text = linkText {
            params["link_text"] = text
        }
        trackEvent(.navClick, parameters: params)
    }
    
    /// Track tab switch within a feature
    /// - Parameters:
    ///   - feature: The feature name
    ///   - tabName: The name of the tab
    ///   - projectId: The project ID (optional)
    func trackTabSwitch(feature: String, tabName: String, projectId: Int? = nil) {
        var params: [String: Any] = [
            "feature": feature,
            "tab_name": tabName
        ]
        if let projectId = projectId {
            params["project_id"] = String(projectId)
        }
        trackEvent(.featureTabSwitch, parameters: params)
    }
    
    // MARK: - User Properties
    
    /// Set user ID for analytics (call after login)
    /// - Parameter userId: The user ID
    func setUserId(_ userId: Int?) {
        if let userId = userId {
            self.userID = String(userId)
            Analytics.setUserID(String(userId))
            if isDebugEnabled || debugMode {
                print("📊 [Analytics] Set User ID: \(userId)")
            }
        } else {
            self.userID = nil
            Analytics.setUserID(nil)
            if isDebugEnabled || debugMode {
                print("📊 [Analytics] Cleared User ID")
            }
        }
    }
    
    /// Set user property
    /// - Parameters:
    ///   - name: Property name
    ///   - value: Property value
    func setUserProperty(name: String, value: String?) {
        Analytics.setUserProperty(value, forName: name)
        if isDebugEnabled || debugMode {
            print("📊 [Analytics] Set User Property: \(name) = \(value ?? "nil")")
        }
    }
    
    /// Set tenant ID as user property
    /// - Parameter tenantId: The tenant ID
    func setTenantId(_ tenantId: Int?) {
        setUserProperty(name: "tenant_id", value: tenantId.map { String($0) })
    }
}

// MARK: - SwiftUI View Extension for Screen Tracking

extension View {
    /// Track screen view when the view appears
    /// - Parameters:
    ///   - screenName: The name of the screen to track
    ///   - projectId: Associated project ID (optional)
    /// - Returns: Modified view with tracking
    func trackScreen(_ screenName: String, projectId: Int? = nil) -> some View {
        self.onAppear {
            AnalyticsManager.shared.trackScreenView(screenName, projectId: projectId)
        }
    }
}

// MARK: - View Modifier for More Control

struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    let screenClass: String?
    let projectId: Int?
    
    init(screenName: String, screenClass: String? = nil, projectId: Int? = nil) {
        self.screenName = screenName
        self.screenClass = screenClass
        self.projectId = projectId
    }
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsManager.shared.trackScreenView(
                    screenName,
                    screenClass: screenClass,
                    projectId: projectId
                )
            }
    }
}

extension View {
    /// Apply screen tracking with more options
    func trackScreenView(
        _ screenName: String,
        screenClass: String? = nil,
        projectId: Int? = nil
    ) -> some View {
        modifier(ScreenTrackingModifier(
            screenName: screenName,
            screenClass: screenClass,
            projectId: projectId
        ))
    }
}
