//
//  ChatViewModel.swift
//  macai
//
//  Created by Renat on 29.07.2024.
//

import Combine
import Foundation
import SwiftUI

class ChatViewModel: ObservableObject {
    @Published var messages: NSOrderedSet
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext

    private var _messageManager: MessageManager?
    private var messageManager: MessageManager {
        get {
            if _messageManager == nil {
                _messageManager = createMessageManager()
            }
            return _messageManager!
        }
        set {
            _messageManager = newValue
        }
    }

    private var cancellables = Set<AnyCancellable>()

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext
    }

    func sendMessage(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        self.messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we're using Google Search followed by LLM
        if getApiServiceName() == "googlesearch" {
            // Create a new user message
            let ownMessage = MessageEntity(context: viewContext)
            ownMessage.id = Int64(chat.messages.count + 1)
            ownMessage.body = message
            ownMessage.timestamp = Date()
            ownMessage.own = true
            ownMessage.chat = chat
            chat.addToMessages(ownMessage)
            chat.updatedDate = Date()
            
            // Add system message indicating search is being performed
            let searchingMessage = MessageEntity(context: viewContext)
            searchingMessage.id = Int64(chat.messages.count + 1)
            searchingMessage.body = "🔍 Searching the web for information..."
            searchingMessage.timestamp = Date()
            searchingMessage.own = false
            searchingMessage.chat = chat
            chat.addToMessages(searchingMessage)
            
            try? viewContext.save()
            chat.objectWillChange.send()
            
            // First, send the query to Google Search
            self.messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] searchResult in
                guard let self = self else { return }
                
                switch searchResult {
                case .success:
                    // After getting search results, send to configured default LLM (if available)
                    if let defaultLLMChat = self.getDefaultLLMChat() {
                        // Update the message to show processing
                        if let lastMessage = chat.lastMessage, !lastMessage.own {
                            lastMessage.body += "\n\n⏳ Processing results with AI..."
                            try? self.viewContext.save()
                            self.chat.objectWillChange.send()
                        }
                        
                        // Create prompt with search results
                        let searchResultMessage = self.getLastNonUserMessage()?.body ?? ""
                        let llmPrompt = """
                        I searched the web for: "\(message)"
                        
                        Here are the search results:
                        \(searchResultMessage)
                        
                        Based on these search results, please answer my original question in a comprehensive and helpful way. Cite sources when appropriate.
                        """
                        
                        // Create a MessageManager for the default LLM
                        let llmMessageManager = self.createLLMMessageManager(chat: defaultLLMChat)
                        
                        // Send the message to LLM
                        llmMessageManager.sendMessage(llmPrompt, in: defaultLLMChat, contextSize: contextSize) { [weak self] llmResult in
                            guard let self = self else { return }
                            
                            switch llmResult {
                            case .success:
                                // Get the LLM's response
                                if let llmResponse = defaultLLMChat.lastMessage?.body, !llmResponse.isEmpty {
                                    // Replace the search results with the processed answer
                                    if let lastMessage = self.getLastNonUserMessage() {
                                        lastMessage.body = llmResponse
                                        try? self.viewContext.save()
                                    }
                                }
                                self.chat.objectWillChange.send()
                                completion(.success(()))
                                
                            case .failure(let error):
                                print("Error processing with LLM: \(error)")
                                // Keep the search results if LLM fails
                                completion(.success(()))
                            }
                        }
                    } else {
                        // Just return the search results if no default LLM is available
                        completion(.success(()))
                    }
                    
                case .failure(let error):
                    if let lastMessage = self.getLastNonUserMessage() {
                        lastMessage.body = "❌ Error searching the web: \(error.localizedDescription)"
                        try? self.viewContext.save()
                    }
                    completion(.failure(error))
                }
            }
        } else {
            // Regular message sending for non-search APIs
            self.messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
                switch result {
                case .success:
                    self?.chat.objectWillChange.send()
                    completion(.success(()))
                    self?.reloadMessages()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Helper to get the last non-user message in the chat
    private func getLastNonUserMessage() -> MessageEntity? {
        return chat.messagesArray.reversed().first(where: { !$0.own })
    }
    
    // Helper method to get the default LLM chat configuration
    private func getDefaultLLMChat() -> ChatEntity? {
        // Find a default LLM API service (preferring ChatGPT or Claude)
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "type IN %@", ["chatgpt", "claude", "gemini", "perplexity"])
        fetchRequest.fetchLimit = 1
        
        do {
            let apiServices = try viewContext.fetch(fetchRequest)
            guard let defaultLLMService = apiServices.first else {
                print("No suitable LLM service found for processing search results")
                return nil
            }
            
            // Create a temporary chat using this service
            let tempChat = ChatEntity(context: viewContext)
            tempChat.id = UUID()
            tempChat.name = "SearchProcessor"
            tempChat.createdDate = Date()
            tempChat.updatedDate = Date()
            tempChat.apiService = defaultLLMService
            tempChat.gptModel = defaultLLMService.model ?? "gpt-4o"
            
            // Set system prompt specifically for processing search results
            tempChat.systemMessage = """
            You are an AI assistant that analyzes search results from the web.
            Your task is to:
            1. Extract relevant information from the search results
            2. Synthesize a comprehensive and accurate answer
            3. Cite sources when providing factual information
            4. Be objective and present multiple perspectives when relevant
            5. Indicate clearly if information is missing or uncertain
            """
            tempChat.requestMessages = []
            
            // Don't save this temporary chat to the database
            viewContext.refresh(tempChat, mergeChanges: false)
            
            return tempChat
        } catch {
            print("Error finding default LLM service: \(error)")
            return nil
        }
    }
    
    // Create a message manager for an LLM
    private func createLLMMessageManager(chat: ChatEntity) -> MessageManager {
        guard let apiService = chat.apiService else {
            fatalError("Chat has no API service")
        }
        
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: apiService.id?.uuidString ?? "") ?? ""
        }
        catch {
            print("Error extracting token: \(error)")
        }
        
        let config = APIServiceConfig(
            name: apiService.type ?? "chatgpt",
            apiUrl: apiService.url!,
            apiKey: apiKey,
            model: chat.gptModel
        )
        
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(config: config),
            viewContext: self.viewContext
        )
    }

    func cancelGeneration() {
        messageManager.cancelGeneration()
    }

    func generateChatNameIfNeeded() {
        messageManager.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        messages = self.messages
    }

    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
    }
    
    // For paging/lazy loading support
    func getVisibleMessages(startIndex: Int, count: Int) -> [MessageEntity] {
        let allMessages = self.chat.messagesArray
        guard startIndex < allMessages.count else { return [] }
        
        let endIndex = min(startIndex + count, allMessages.count)
        return Array(allMessages[startIndex..<endIndex])
    }

    private func createMessageManager() -> MessageManager {
        guard let config = self.loadCurrentAPIConfig() else {
            fatalError("No valid API configuration found")
        }
        print(">> Creating new MessageManager with URL: \(config.apiUrl) and model: \(config.model)")
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(config: config),
            viewContext: self.viewContext
        )
    }

    func recreateMessageManager() {
        _messageManager = createMessageManager()
    }

    var canSendMessage: Bool {
        return chat.apiService != nil
    }

    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        guard let apiService = chat.apiService, let apiServiceUrl = apiService.url else {
            return nil
        }

        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: apiService.id?.uuidString ?? "") ?? ""
        }
        catch {
            print("Error extracting token: \(error) for \(apiService.id?.uuidString ?? "")")
        }

        return APIServiceConfig(
            name: getApiServiceName(),
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: chat.gptModel
        )
    }

    private func getApiServiceName() -> String {
        return chat.apiService?.type ?? "chatgpt"
    }
    
    func regenerateChatName() {
        messageManager.generateChatNameIfNeeded(chat: chat, force: true)
    }
}
