//
//  GoogleSearchHandler.swift
//  macai
//
//  Created on 03/04/2025.
//

import Foundation

class GoogleSearchHandler: APIService {
    let name: String = "Google Search"
    let baseURL: URL
    private let config: APIServiceConfiguration
    private let session: URLSession
    private let searchURL: URL
    
    init(config: APIServiceConfiguration, session: URLSession) {
        self.config = config
        self.session = session
        self.baseURL = config.apiUrl
        
        // Construct the search URL with API key
        var components = URLComponents(url: config.apiUrl, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "key", value: config.apiKey)
        ]
        self.searchURL = components.url!
    }
    
    func fetchModels() async throws -> [AIModel] {
        // Google Search doesn't have models like LLMs do
        // Return an array with just the default search engine ID
        return [AIModel(id: self.config.model)]
    }
    
    func sendMessage(_ requestMessages: [[String: String]], temperature: Float, completion: @escaping (Result<String, APIError>) -> Void) {
        // Extract the user's last query from messages
        guard let lastUserMessage = requestMessages.last(where: { $0["role"] == "user" }),
              let query = lastUserMessage["content"] else {
            completion(.failure(.invalidResponse))
            return
        }
        
        // Perform Google search with the query
        performSearch(query: query) { result in
            switch result {
            case .success(let searchResults):
                // Format search results for the LLM
                let formattedResults = self.formatSearchResults(searchResults)
                completion(.success(formattedResults))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            // Extract the user's last query from messages
            guard let lastUserMessage = requestMessages.last(where: { $0["role"] == "user" }),
                  let query = lastUserMessage["content"] else {
                continuation.finish(throwing: APIError.invalidResponse)
                return
            }
            
            // Perform Google search with the query
            self.performSearch(query: query) { result in
                switch result {
                case .success(let searchResults):
                    // Format search results for the LLM
                    let formattedResults = self.formatSearchResults(searchResults)
                    continuation.yield(formattedResults)
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func performSearch(query: String, completion: @escaping (Result<[SearchResult], APIError>) -> Void) {
        // Construct the search URL with the query and API key
        var components = URLComponents(url: self.searchURL, resolvingAgainstBaseURL: true)!
        let existingItems = components.queryItems ?? []
        components.queryItems = existingItems + [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "cx", value: config.model) // Use config.model for Search Engine ID
        ]
        
        guard let url = components.url else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.requestFailed(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }
                
                do {
                    let searchResponse = try JSONDecoder().decode(GoogleSearchResponse.self, from: data)
                    completion(.success(searchResponse.items ?? []))
                } catch {
                    completion(.failure(.decodingFailed(error.localizedDescription)))
                }
                
            case 401:
                completion(.failure(.unauthorized))
            case 429:
                completion(.failure(.rateLimited))
            case 500...599:
                completion(.failure(.serverError("Server error with status code \(httpResponse.statusCode)")))
            default:
                completion(.failure(.unknown("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
    
    private func formatSearchResults(_ results: [SearchResult]) -> String {
        if results.isEmpty {
            return "No search results found."
        }
        
        var formattedResponse = "### Google Search Results:\n\n"
        
        for (index, result) in results.prefix(5).enumerated() {
            formattedResponse += "**\(index + 1). [\(result.title)](\(result.link))**\n"
            formattedResponse += "\(result.snippet)\n\n"
        }
        
        formattedResponse += "\n---\n\nThese search results are from Google Search API. Let me help you understand this information better."
        
        return formattedResponse
    }
}

// MARK: - Data Models
struct GoogleSearchResponse: Codable {
    let kind: String?
    let items: [SearchResult]?
}

struct SearchResult: Codable {
    let title: String
    let link: String
    let snippet: String
}