//
//  MessageManager.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import CoreData
import Foundation

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var cancellationTask: Task<Void, Never>? = nil

    init(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func update(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func sendMessage(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Check if this is a search command
        if shouldPerformSearch(message: message) {
            performGoogleSearch(message: extractSearchQuery(from: message), chat: chat) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let searchResults):
                    // Process the original message and search results with the LLM
                    let enhancedMessage = """
                    \(message)
                    
                    Search Results:
                    \(searchResults)
                    
                    Please analyze these search results and provide a comprehensive answer.
                    """
                    
                    // Now send the enhanced message to the LLM
                    let requestMessages = self.prepareRequestMessages(userMessage: enhancedMessage, chat: chat, contextSize: contextSize)
                    let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
                    
                    self.apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
                        guard let self = self else { return }
                        
                        switch result {
                        case .success(let messageBody):
                            chat.waitingForResponse = false
                            self.addMessageToChat(chat: chat, message: messageBody)
                            self.addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                            self.viewContext.saveWithRetry(attempts: 1)
                            completion(.success(()))
                            
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                    
                case .failure(let error):
                    // If search fails, still try to answer with just the LLM
                    let requestMessages = self.prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
                    let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
                    
                    self.apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
                        guard let self = self else { return }
                        
                        switch result {
                        case .success(let messageBody):
                            chat.waitingForResponse = false
                            self.addMessageToChat(chat: chat, message: messageBody)
                            self.addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                            self.viewContext.saveWithRetry(attempts: 1)
                            completion(.success(()))
                            
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                }
            }
        } else {
            // Regular message processing without search
            let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
            chat.waitingForResponse = true
            let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

            apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let messageBody):
                    chat.waitingForResponse = false
                    addMessageToChat(chat: chat, message: messageBody)
                    addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                    self.viewContext.saveWithRetry(attempts: 1)
                    completion(.success(()))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Check if message contains search intent
    private func shouldPerformSearch(message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        let searchTerms = [
            "погугли", "погуглить", "поищи", "найди в гугл", "найди информацию", 
            "найди в интернете", "google", "search for", "look up", "find information about",
            "search the web for", "search online for"
        ]
        
        return searchTerms.contains { lowercasedMessage.contains($0) }
    }
    
    // Extract the actual search query from the message
    private func extractSearchQuery(from message: String) -> String {
        let lowercasedMessage = message.lowercased()
        let searchTerms = [
            "погугли ", "погуглить ", "поищи ", "найди в гугл ", "найди информацию о ", 
            "найди в интернете ", "google ", "search for ", "look up ", "find information about ",
            "search the web for ", "search online for "
        ]
        
        var query = message
        for term in searchTerms {
            if lowercasedMessage.contains(term) {
                if let range = message.range(of: term, options: .caseInsensitive) {
                    query = String(message[range.upperBound...])
                    break
                }
            }
        }
        
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Perform Google search using the Search API
    private func performGoogleSearch(message: String, chat: ChatEntity, completion: @escaping (Result<String, Error>) -> Void) {
        // Find a Google Search API configuration
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "type == %@", "googlesearch")
        fetchRequest.fetchLimit = 1
        
        do {
            let searchServices = try viewContext.fetch(fetchRequest)
            
            if let googleService = searchServices.first, let serviceURL = googleService.url {
                var apiKey = ""
                do {
                    apiKey = try TokenManager.getToken(for: googleService.id?.uuidString ?? "") ?? ""
                }
                catch {
                    print("Error extracting token: \(error)")
                    completion(.failure(error))
                    return
                }
                
                let config = APIServiceConfig(
                    name: "googlesearch",
                    apiUrl: serviceURL,
                    apiKey: apiKey,
                    model: googleService.model ?? ""
                )
                
                let searchAPI = APIServiceFactory.createAPIService(config: config)
                let requestMessages = [["role": "user", "content": message]]
                
                searchAPI.sendMessage(requestMessages, temperature: 0.7) { result in
                    switch result {
                    case .success(let searchResults):
                        completion(.success(searchResults))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                // No Google Search configuration found
                completion(.failure(APIError.noApiService("Google Search not configured")))
            }
        } catch {
            completion(.failure(error))
        }
    }

    @MainActor
    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Check if this is a search command
        if shouldPerformSearch(message: message) {
            // Add a user message to the chat
            let userMessage = MessageEntity(context: viewContext)
            userMessage.id = Int64(chat.messages.count + 1)
            userMessage.body = message
            userMessage.timestamp = Date()
            userMessage.own = true
            userMessage.chat = chat
            chat.addToMessages(userMessage)
            
            // Add an assistant message indicating search is in progress
            let searchingMessage = MessageEntity(context: viewContext)
            searchingMessage.id = Int64(chat.messages.count + 1)
            searchingMessage.body = "🔍 Searching the web for information..."
            searchingMessage.timestamp = Date()
            searchingMessage.own = false
            searchingMessage.chat = chat
            chat.addToMessages(searchingMessage)
            
            chat.updatedDate = Date()
            try? viewContext.save()
            chat.objectWillChange.send()
            
            // Perform search
            performGoogleSearch(message: extractSearchQuery(from: message), chat: chat) { [weak self] result in
                guard let self = self else { return }
                
                Task {
                    switch result {
                    case .success(let searchResults):
                        // Update the message to show search results are being processed
                        if let lastMessage = chat.lastMessage, !lastMessage.own {
                            lastMessage.body = "🔍 Found search results. Processing with AI..."
                            try? self.viewContext.save()
                            chat.objectWillChange.send()
                        }
                        
                        // Process the original message and search results with the LLM
                        let enhancedMessage = """
                        \(message)
                        
                        Search Results:
                        \(searchResults)
                        
                        Please analyze these search results and provide a comprehensive answer.
                        """
                        
                        // Now send the enhanced message to the LLM
                        let requestMessages = self.prepareRequestMessages(userMessage: enhancedMessage, chat: chat, contextSize: contextSize)
                        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
                        
                        do {
                            let stream = try await self.apiService.sendMessageStream(requestMessages, temperature: temperature)
                            var accumulatedResponse = ""
                            
                            for try await chunk in stream {
                                if Task.isCancelled {
                                    break
                                }
                                
                                accumulatedResponse += chunk
                                
                                if let lastMessage = chat.lastMessage, !lastMessage.own {
                                    let now = Date()
                                    if now.timeIntervalSince(self.lastUpdateTime) >= self.updateInterval {
                                        self.updateLastMessage(
                                            chat: chat,
                                            lastMessage: lastMessage,
                                            accumulatedResponse: accumulatedResponse
                                        )
                                        self.lastUpdateTime = now
                                    }
                                }
                            }
                            
                            if let lastMessage = chat.lastMessage, !lastMessage.own {
                                self.updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulatedResponse
                                )
                                self.addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                            }
                            
                            completion(.success(()))
                        } catch {
                            if Task.isCancelled {
                                print("Stream was cancelled")
                                completion(.success(()))
                            } else {
                                print("Streaming error: \(error)")
                                completion(.failure(error))
                            }
                        }
                        
                    case .failure(let error):
                        // Update the message to show search failed
                        if let lastMessage = chat.lastMessage, !lastMessage.own {
                            lastMessage.body = "❌ Search failed: \(error.localizedDescription). Trying to answer without search results..."
                            try? self.viewContext.save()
                            chat.objectWillChange.send()
                        }
                        
                        // Process the message normally without search results
                        let requestMessages = self.prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
                        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
                        
                        do {
                            let stream = try await self.apiService.sendMessageStream(requestMessages, temperature: temperature)
                            var accumulatedResponse = ""
                            
                            for try await chunk in stream {
                                if Task.isCancelled {
                                    break
                                }
                                
                                accumulatedResponse += chunk
                                
                                if let lastMessage = chat.lastMessage, !lastMessage.own {
                                    let now = Date()
                                    if now.timeIntervalSince(self.lastUpdateTime) >= self.updateInterval {
                                        self.updateLastMessage(
                                            chat: chat,
                                            lastMessage: lastMessage,
                                            accumulatedResponse: accumulatedResponse
                                        )
                                        self.lastUpdateTime = now
                                    }
                                }
                            }
                            
                            if let lastMessage = chat.lastMessage, !lastMessage.own {
                                self.updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulatedResponse
                                )
                                self.addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                            }
                            
                            completion(.success(()))
                        } catch {
                            if Task.isCancelled {
                                print("Stream was cancelled")
                                completion(.success(()))
                            } else {
                                print("Streaming error: \(error)")
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        } else {
            // Regular message processing without search
            let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
            let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

            cancellationTask = Task {
                do {
                    let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                    var accumulatedResponse = ""
                    chat.waitingForResponse = true

                    for try await chunk in stream {
                        if Task.isCancelled {
                            break
                        }

                        accumulatedResponse += chunk
                        if let lastMessage = chat.lastMessage {
                            if lastMessage.own {
                                self.addMessageToChat(chat: chat, message: accumulatedResponse)
                            }
                            else {
                                let now = Date()
                                if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                                    updateLastMessage(
                                        chat: chat,
                                        lastMessage: lastMessage,
                                        accumulatedResponse: accumulatedResponse
                                    )
                                    lastUpdateTime = now
                                }
                            }
                        }
                    }
                    updateLastMessage(chat: chat, lastMessage: chat.lastMessage!, accumulatedResponse: accumulatedResponse)
                    addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                    completion(.success(()))
                }
                catch {
                    if Task.isCancelled {
                        print("Stream was cancelled")
                        completion(.success(()))
                    } else {
                        print("Streaming error: \(error)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    // For direct streaming without modifying chat state (used for search+LLM flow)
    func sendMessageStream(
        _ message: String,
        contextSize: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        let requestMessages = [
            ["role": "system", "content": "You are an AI assistant that processes search results."],
            ["role": "user", "content": message]
        ]
        let temperature = AppConstants.defaultTemperatureForChat.roundedToOneDecimal()
        
        return try await apiService.sendMessageStream(requestMessages, temperature: temperature)
    }

    func cancelGeneration() {
        cancellationTask?.cancel()
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "", chat.messages.count > 0 else {
            #if DEBUG
                print("Chat name not needed, skipping generation")
            #endif
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        apiService.sendMessage(requestMessages, temperature: AppConstants.defaultTemperatureForChatNameGeneration) {
            [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                let chatName = self.sanitizeChatName(messageBody)
                chat.name = chatName
                self.viewContext.saveWithRetry(attempts: 3)
            case .failure(let error):
                print("Error generating chat name: \(error)")
            }
        }
    }

    private func sanitizeChatName(_ rawName: String) -> String {
        if let range = rawName.range(of: "**(.+?)**", options: .regularExpression) {
            return String(rawName[range]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        }

        let lines = rawName.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return lastNonEmptyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAPI(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var requestMessages: [[String: String]] = []
        var temperature = AppConstants.defaultPersonaTemperature

        if !AppConstants.openAiReasoningModels.contains(model) {
            requestMessages.append([
                "role": "system",
                "content": "You are a test assistant.",
            ])
        }
        else {
            temperature = 1
        }

        requestMessages.append(
            [
                "role": "user",
                "content": "This is a test message.",
            ])

        apiService.sendMessage(requestMessages, temperature: temperature) { result in
            switch result {
            case .success(_):
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func prepareRequestMessages(userMessage: String, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        return constructRequestMessages(chat: chat, forUserMessage: userMessage, contextSize: contextSize)
    }

    private func addMessageToChat(chat: ChatEntity, message: String) {
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = message
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        chat.objectWillChange.send()
    }

    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        chat.requestMessages.append(["role": role, "content": content])
        self.viewContext.saveWithRetry(attempts: 1)
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String) {
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        chat.waitingForResponse = false
        lastMessage.body = accumulatedResponse
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()

        Task {
            await MainActor.run {
                self.viewContext.saveWithRetry(attempts: 1)
            }
        }
    }

    private func constructRequestMessages(chat: ChatEntity, forUserMessage userMessage: String?, contextSize: Int)
        -> [[String: String]]
    {
        var messages: [[String: String]] = []

        if !AppConstants.openAiReasoningModels.contains(chat.gptModel) {
            messages.append([
                "role": "system",
                "content": chat.systemMessage,
            ])
        }
        else {
            // Models like o1-mini and o1-preview don't support "system" role. However, we can pass the system message with "user" role instead.
            messages.append([
                "role": "user",
                "content": "Take this message as the system message: \(chat.systemMessage)",
            ])
        }

        let sortedMessages = chat.messagesArray
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(contextSize)

        // Add conversation history
        for message in sortedMessages {
            messages.append([
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ])
        }

        // Add new user message if provided
        let lastMessage = messages.last?["content"] ?? ""
        if lastMessage != userMessage {
            if let userMessage = userMessage {
                messages.append([
                    "role": "user",
                    "content": userMessage,
                ])
            }
        }

        return messages
    }
}
