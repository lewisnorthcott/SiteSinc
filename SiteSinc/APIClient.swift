//
//  APIClient.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import Foundation

struct APIClient {
    #if DEBUG
    static let baseURL = "http://localhost:3000/api" // Local development
    #else
    static let baseURL = "https://your-production-api.com/api" // Production
    #endif
    
    static func login(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
            let url = URL(string: "\(baseURL)/auth/login")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let params = ["email": email, "password": password]
            request.httpBody = try? JSONEncoder().encode(params)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data, let loginResponse = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    return
                }
                completion(.success(loginResponse.token))
            }.resume()
        }

    static func fetchTenants(token: String, completion: @escaping (Result<[Tenant], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/tenants")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Fetch tenants error: \(error)")
                completion(.failure(error))
                return
            }
            guard let data = data else {
                print("No data returned from tenants endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let tenants = try JSONDecoder().decode([Tenant].self, from: data)
                print("Fetched tenants: \(tenants)")
                completion(.success(tenants))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }

    static func selectTenant(token: String, tenantId: Int, completion: @escaping (Result<(String, User), Error>) -> Void) {
        let url = URL(string: "\(baseURL)/auth/select-tenant")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let params = ["tenantId": tenantId]
        request.httpBody = try? JSONEncoder().encode(params)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                struct Response: Decodable {
                    let token: String
                    let user: User
                }
                let response = try JSONDecoder().decode(Response.self, from: data)
                completion(.success((response.token, response.user)))
            } catch {
                print("Decoding error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    static func fetchProjects(token: String, completion: @escaping (Result<[Project], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let projects = try? JSONDecoder().decode([Project].self, from: data) else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            completion(.success(projects))
        }.resume()
    }
    
    static func fetchDrawings(projectId: Int, token: String, completion: @escaping (Result<[Drawing], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/drawings?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let drawingResponse = try JSONDecoder().decode(DrawingResponse.self, from: data)
                let filteredDrawings = drawingResponse.drawings.filter { $0.projectId == projectId }
                completion(.success(filteredDrawings))
            } catch {
                print("Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(jsonString)")
                }
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Add download helper
    static func downloadFile(from urlString: String, to localPath: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No file downloaded"])))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: localPath.path) {
                    try FileManager.default.removeItem(at: localPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: localPath)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}


struct Tenant: Codable, Identifiable {
    let id: Int
    let name: String
}

struct User: Codable {
    let id: Int
    let email: String?
    let firstName: String?
    let lastName: String?
    let tenantId: Int?
    let companyId: Int?
    let roles: [String]?
    let permissions: [String]?
    let isSubscriptionOwner: Bool?
}

struct LoginResponse: Decodable {
    let token: String
}

struct Project: Decodable, Identifiable {
    let id: Int
    let name: String
    let reference: String
    let logoUrl: String?
    let location: String?
    let projectStatus: String?
    let description: String?
    let tenantId: Int?

}





struct DrawingResponse: Decodable {
    let drawings: [Drawing]
}

struct Drawing: Decodable, Identifiable {
    let id: Int
    let title: String
    let number: String
    let projectId: Int
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let revisions: [Revision]
    let company: Company? // Add company field
    let discipline: String?
    let projectDiscipline: ProjectDiscipline?
    let projectDrawingType: ProjectDrawingType?
    var isOffline: Bool?
}

struct ProjectDiscipline: Decodable {
    let name: String?
}

struct ProjectDrawingType: Decodable {
    let name: String?
}

struct Company: Decodable {
    let id: Int
    let name: String
    let createdAt: String?
    let updatedAt: String?
}

struct Revision: Decodable {
    let id: Int
    let versionNumber: Int
    let status: String
    let drawingFiles: [DrawingFile]
    let createdAt: String?
    let revisionNumber: String?
    
}

struct DrawingFile: Decodable {
    let id: Int
    let downloadUrl: String
    let fileName: String
    let fileType: String
    let createdAt: String?
    var localPath: URL?
    
}
