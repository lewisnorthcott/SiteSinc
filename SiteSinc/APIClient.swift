//
//  APIClient.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import Foundation

struct APIClient {
    static let baseURL = "http://localhost:3000/api" // e.g., "http://localhost:3000"
    
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
}

// Models (unchanged)
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
}

struct DrawingFile: Decodable {
    let id: Int
    let downloadUrl: String
    let fileName: String
    let fileType: String
}
