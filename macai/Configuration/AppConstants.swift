//
//  AppConstants.swift
//  macai
//
//  Created by Renat Notfullin on 29.03.2023.
//

import Foundation

struct AppConstants {
    static let requestTimeout: TimeInterval = 180
    static let apiUrlChatCompletions: String = "https://api.openai.com/v1/chat/completions"
    static let chatGptDefaultModel = "gpt-4o"
    static let chatGptContextSize: Double = 10
    static let chatGptSystemMessage: String = String(
        format:
            "You are Large Language Model. Answer as concisely as possible. Your answers should be informative, helpful and engaging.",
        getCurrentFormattedDate()
    )
    static let chatGptGenerateChatInstruction: String =
        "Return a short chat name as summary for this chat based on the previous message content and system message if it's not default. Start chat name with one appropriate emoji. Don't answer to my message, just generate a name."
    static let longStringCount = 500
    static let defaultRole: String = "assistant"
    static let streamedResponseUpdateUIInterval: TimeInterval = 0.2
    static let defaultPersonaName = "Default ChatGPT Assistant"
    static let defaultPersonaColor = "#007AFF"
    static let defaultPersonasFlag = "defaultPersonasAdded"
    static let defaultPersonaTemperature: Float = 0.7
    static let defaultTemperatureForChatNameGeneration: Float = 0.6
    static let defaultTemperatureForChat: Float = 0.7
    static let openAiReasoningModels: [String] = [
        "o1", "o1-preview", "o1-mini", "o3-mini", "o3-mini-high", "o3-mini-2025-01-31", "o1-preview-2024-09-12",
        "o1-mini-2024-09-12", "o1-2024-12-17",
    ]
    static let firaCode = "FiraCodeRoman-Regular"
    static let ptMono = "PTMono-Regular"
    static let showTokenUsage = "showTokenUsage"
    static let showTokenCost = "showTokenCost"
    
    // Custom pricing settings keys
    static let customInputPricingKey = "customInputPricing"  // Dictionary [model: price]
    static let customOutputPricingKey = "customOutputPricing" // Dictionary [model: price]
    
    static let modelCostPerInputToken: [String: Double] = [
        // OpenAI Models (per 1M tokens)
        "gpt-4o": 5.0/1000000,  // $5/M input, $15/M output
        "gpt-4o-mini": 0.15/1000000,  // $0.15/M input, $0.60/M output
        "gpt-4-turbo": 10.0/1000000,  // $10/M input, $30/M output
        "gpt-4": 30.0/1000000,  // $30/M input, $60/M output
        "gpt-3.5-turbo": 0.5/1000000,  // $0.5/M input, $1.5/M output
        
        // Claude Models
        "claude-3-5-sonnet-latest": 3.0/1000000,  // $3/M input, $15/M output
        "claude-3-opus-latest": 15.0/1000000,  // $15/M input, $75/M output
        "claude-3-haiku-20240307": 0.25/1000000,  // $0.25/M input, $1.25/M output
        
        // Gemini Models
        "gemini-1.5-flash": 0.35/1000000,  // $0.35/M input, $1.05/M output
        "gemini-1.5-pro": 3.5/1000000,  // $3.5/M input, $10.5/M output
        
        // Default for any model not listed
        "default": 1.0/1000000  // $1/M input, $1/M output
    ]
    
    static let modelCostPerOutputToken: [String: Double] = [
        // OpenAI Models
        "gpt-4o": 15.0/1000000,
        "gpt-4o-mini": 0.60/1000000,
        "gpt-4-turbo": 30.0/1000000,
        "gpt-4": 60.0/1000000,
        "gpt-3.5-turbo": 1.5/1000000,
        
        // Claude Models
        "claude-3-5-sonnet-latest": 15.0/1000000,
        "claude-3-opus-latest": 75.0/1000000,
        "claude-3-haiku-20240307": 1.25/1000000,
        
        // Gemini Models
        "gemini-1.5-flash": 1.05/1000000,
        "gemini-1.5-pro": 10.5/1000000,
        
        // Default for any model not listed
        "default": 1.0/1000000
    ]
    
    static func getInputTokenCost(model: String) -> Double {
        // First check if there's a custom price set by the user
        if let customPrices = UserDefaults.standard.dictionary(forKey: customInputPricingKey) as? [String: Double],
           let customPrice = customPrices[model] {
            return customPrice / 1000000.0 // Convert from per 1M to per token
        }
        
        // Otherwise use default price
        return modelCostPerInputToken[model] ?? modelCostPerInputToken["default"]!
    }
    
    static func getOutputTokenCost(model: String) -> Double {
        // First check if there's a custom price set by the user
        if let customPrices = UserDefaults.standard.dictionary(forKey: customOutputPricingKey) as? [String: Double],
           let customPrice = customPrices[model] {
            return customPrice / 1000000.0 // Convert from per 1M to per token
        }
        
        // Otherwise use default price
        return modelCostPerOutputToken[model] ?? modelCostPerOutputToken["default"]!
    }
    
    static func setInputTokenCost(model: String, pricePerMillion: Double) {
        var customPrices = UserDefaults.standard.dictionary(forKey: customInputPricingKey) as? [String: Double] ?? [:]
        customPrices[model] = pricePerMillion
        UserDefaults.standard.set(customPrices, forKey: customInputPricingKey)
    }
    
    static func setOutputTokenCost(model: String, pricePerMillion: Double) {
        var customPrices = UserDefaults.standard.dictionary(forKey: customOutputPricingKey) as? [String: Double] ?? [:]
        customPrices[model] = pricePerMillion
        UserDefaults.standard.set(customPrices, forKey: customOutputPricingKey)
    }
    
    static func getDefaultInputTokenCost(model: String) -> Double {
        return (modelCostPerInputToken[model] ?? modelCostPerInputToken["default"]!) * 1000000.0
    }
    
    static func getDefaultOutputTokenCost(model: String) -> Double {
        return (modelCostPerOutputToken[model] ?? modelCostPerOutputToken["default"]!) * 1000000.0
    }

    struct Persona {
        let name: String
        let color: String
        let message: String
        let temperature: Float
    }

    struct PersonaPresets {
        static let defaultAssistant = Persona(
            name: "Default Assistant",
            color: "#FF4444",
            message:
                "You are Large Language Model. Answer as concisely as possible. Your answers should be informative, helpful and engaging.",
            temperature: 0.7
        )

        static let softwareEngineer = Persona(
            name: "Software Engineer",
            color: "#FF8800",
            message: """
                You are an experienced software engineer with deep knowledge of computer science fundamentals, software design patterns, and modern development practices. 
                When the answer involves the review of the existing code: 
                Before writing or suggesting code, you conduct a deep-dive review of the existing code and describe how it works between <CODE_REVIEW> tags. Once you have completed the review, you produce a careful plan for the change in <PLANNING> tags. Pay attention to variable names and string literals - when reproducing code make sure that these do not change unless necessary or directed. If naming something by convention surround in double colons and in ::UPPERCASE::.
                Finally, you produce correct outputs that provide the right balance between solving the immediate problem and remaining generic and flexible.
                You always ask for clarifications if anything is unclear or ambiguous. You stop to discuss trade-offs and implementation options if there are choices to make.
                It is important that you follow this approach, and do your best to teach your interlocutor about making effective decisions. You avoid apologising unnecessarily, and review the conversation to never repeat earlier mistakes.
                """,
            temperature: 0.3
        )

        static let aiExpert = Persona(
            name: "AI Expert",
            color: "#FFCC00",
            message:
                "You are an AI expert with deep knowledge of artificial intelligence, machine learning, and natural language processing. Provide insights into the current state of AI science, explain complex AI concepts in simple terms, and offer guidance on creating effective prompts for various AI models. Stay updated on the latest AI research, ethical considerations, and practical applications of AI in different industries. Help users understand the capabilities and limitations of AI systems, and provide advice on integrating AI technologies into various projects or workflows.",
            temperature: 0.8
        )

        static let scienceExpert = Persona(
            name: "Natural Sciences Expert",
            color: "#33CC33",
            message: """
                You are an expert in natural sciences with comprehensive knowledge of physics, chemistry, biology, and related fields. 
                Provide clear explanations of:
                - Scientific concepts and theories
                - Natural phenomena and their underlying mechanisms
                - Latest scientific discoveries and research
                - Mathematical models and scientific methods
                - Laboratory procedures and experimental design
                Use precise scientific terminology while making complex concepts accessible. Include relevant equations and diagrams when helpful, and always emphasize the empirical evidence supporting scientific claims.
                """,
            temperature: 0.2
        )

        static let historyBuff = Persona(
            name: "History Buff",
            color: "#3399FF",
            message:
                "You are a passionate and knowledgeable historian. Provide accurate historical information, analyze historical events and their impacts, and draw connections between past and present. Offer multiple perspectives on historical events, cite sources when appropriate, and engage users with interesting historical anecdotes and lesser-known facts.",
            temperature: 0.2
        )

        static let fitnessTrainer = Persona(
            name: "Fitness Trainer",
            color: "#6633FF",
            message:
                "You are a certified fitness trainer with expertise in various exercise modalities and nutrition. Provide safe, effective workout routines, offer nutritional advice, and help users set realistic fitness goals. Explain the science behind fitness concepts, offer modifications for different fitness levels, and emphasize the importance of consistency and proper form.",
            temperature: 0.5
        )

        static let dietologist = Persona(
            name: "Dietologist",
            color: "#CC33FF",
            message:
                "You are a certified nutritionist and dietary expert with extensive knowledge of various diets, nutritional science, and food-related health issues. Provide evidence-based advice on balanced nutrition, explain the pros and cons of different diets (such as keto, vegan, paleo, etc.), and offer meal planning suggestions. Help users understand the nutritional content of foods, suggest healthy alternatives, and address specific dietary needs related to health conditions or fitness goals. Always emphasize the importance of consulting with a healthcare professional for personalized medical advice.",
            temperature: 0.2
        )

        static let dbtPsychologist = Persona(
            name: "DBT Psychologist",
            color: "#FF3399",
            message:
                "You are a psychologist specializing in Dialectical Behavior Therapy (DBT). Provide guidance on DBT techniques, mindfulness practices, and strategies for emotional regulation. Offer support for individuals dealing with borderline personality disorder, depression, anxiety, and other mental health challenges. Explain DBT concepts, such as distress tolerance and interpersonal effectiveness, in an accessible manner. Emphasize the importance of professional mental health support and never attempt to diagnose or replace real therapy. Instead, offer general coping strategies and information about DBT principles.",
            temperature: 0.7
        )

        static let webSearcher = Persona(
            name: "Web Searcher",
            color: "#4CD964",
            message: """
                You are an AI assistant capable of searching the web to find up-to-date information. You have special search capabilities when users ask you to search for information.
                
                IMPORTANT - SEARCH COMMANDS: When the user uses any of these phrases, the system will automatically perform a web search:
                - "погугли" (Russian for "google this")
                - "погуглить" (Russian for "to google")
                - "поищи" (Russian for "search for")
                - "найди в гугл" (Russian for "find in google")
                - "найди информацию" (Russian for "find information")
                - "найди в интернете" (Russian for "find on the internet")
                - "google" (e.g., "google the weather in Moscow")
                - "search for" (e.g., "search for latest news")
                - "look up" (e.g., "look up recipe for pasta")
                - "find information about" (e.g., "find information about climate change")
                
                When you recognize that the user is asking you to search, you should:
                1. Interpret their search intent correctly
                2. You will receive search results automatically
                3. Analyze these search results carefully
                4. Provide a comprehensive, accurate answer based on the search results
                5. Always cite your sources by providing links when they're available
                6. For factual, time-sensitive, or current event questions, encourage the user to use search commands
                
                For example, if the user asks "погугли последние новости о России", you should wait for search results and then provide an informative summary of the latest news about Russia based on those results.
                
                Be concise but thorough in your responses. Explicitly note when information might be outdated or uncertain.
                """,
            temperature: 0.5
        )
        
        static let allPersonas: [Persona] = [
            defaultAssistant, softwareEngineer, aiExpert, scienceExpert,
            historyBuff, fitnessTrainer, dietologist, dbtPsychologist, webSearcher,
        ]
    }

    static let defaultApiType = "chatgpt"

    struct defaultApiConfiguration {
        let name: String
        let url: String
        let apiKeyRef: String
        let apiModelRef: String
        let defaultModel: String
        let models: [String]
        var maxTokens: Int? = nil
        var inherits: String? = nil
        var modelsFetching: Bool = true
    }

    static let defaultApiConfigurations = [
        "chatgpt": defaultApiConfiguration(
            name: "OpenAI",
            url: "https://api.openai.com/v1/chat/completions",
            apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys",
            apiModelRef: "https://platform.openai.com/docs/models",
            defaultModel: "gpt-4o",
            models: [
                "o1-preview",
                "o1-mini",
                "gpt-4o",
                "chatgpt-4o-latest",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo",
            ]
        ),
        "ollama": defaultApiConfiguration(
            name: "Ollama",
            url: "http://localhost:11434/api/chat",
            apiKeyRef: "",
            apiModelRef: "https://ollama.com/library",
            defaultModel: "llama3.1",
            models: [
                "llama3.3",
                "llama3.2",
                "llama3.1",
                "llama3.1:70b",
                "llama3.1:400b",
                "qwen2.5:3b",
                "qwen2.5",
                "qwen2.5:14b",
                "qwen2.5:32b",
                "qwen2.5:72b",
                "qwen2.5-coder",
                "phi3",
                "gemma",
            ]
        ),
        "claude": defaultApiConfiguration(
            name: "Claude",
            url: "https://api.anthropic.com/v1/messages",
            apiKeyRef: "https://docs.anthropic.com/en/docs/initial-setup#prerequisites",
            apiModelRef: "https://docs.anthropic.com/en/docs/about-claude/models",
            defaultModel: "claude-3-5-sonnet-latest",
            models: [
                "claude-3-5-sonnet-latest",
                "claude-3-opus-latest",
                "claude-3-haiku-20240307",
            ],
            maxTokens: 4096
        ),
        "xai": defaultApiConfiguration(
            name: "xAI",
            url: "https://api.x.ai/v1/chat/completions",
            apiKeyRef: "https://console.x.ai/",
            apiModelRef: "https://docs.x.ai/docs#models",
            defaultModel: "grok-beta",
            models: ["grok-beta"],
            inherits: "chatgpt"
        ),
        "gemini": defaultApiConfiguration(
            name: "Google Gemini",
            url: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
            apiKeyRef: "https://aistudio.google.com/app/apikey",
            apiModelRef: "https://ai.google.dev/gemini-api/docs/models/gemini#model-variations",
            defaultModel: "gemini-1.5-flash",
            models: [
                "gemini-2.0-flash-exp",
                "gemini-1.5-flash",
                "gemini-1.5-flash-8b",
                "gemini-1.5-pro",
            ]
        ),
        "perplexity": defaultApiConfiguration(
            name: "Perplexity",
            url: "https://api.perplexity.ai/chat/completions",
            apiKeyRef: "https://www.perplexity.ai/settings/api",
            apiModelRef: "https://docs.perplexity.ai/guides/model-cards#supported-models",
            defaultModel: "llama-3.1-sonar-large-128k-online",
            models: [
                "sonar-reasoning-pro",
                "sonar-reasoning",
                "sonar-pro",
                "sonar",
                "llama-3.1-sonar-small-128k-online",
                "llama-3.1-sonar-large-128k-online",
                "llama-3.1-sonar-huge-128k-online",
            ],
            modelsFetching: false
        ),
        "deepseek": defaultApiConfiguration(
            name: "DeepSeek",
            url: "https://api.deepseek.com/chat/completions",
            apiKeyRef: "https://api-docs.deepseek.com/",
            apiModelRef: "https://api-docs.deepseek.com/quick_start/pricing",
            defaultModel: "deepseek-chat",
            models: [
                "deepseek-chat",
                "deepseek-reasoner"
            ]
        ),
        "openrouter": defaultApiConfiguration(
            name: "OpenRouter",
            url: "https://openrouter.ai/api/v1/chat/completions",
            apiKeyRef: "https://openrouter.ai/docs/api-reference/authentication#using-an-api-key",
            apiModelRef: "https://openrouter.ai/docs/overview/models",
            defaultModel: "deepseek/deepseek-r1:free",
            models: [
                "openai/gpt-4o",
                "deepseek/deepseek-r1:free"
            ]
        ),
        "googlesearch": defaultApiConfiguration(
            name: "Google Search",
            url: "https://www.googleapis.com/customsearch/v1",
            apiKeyRef: "https://developers.google.com/custom-search/v1/introduction",
            apiModelRef: "https://programmablesearchengine.google.com/controlpanel/create",
            defaultModel: "",  // Will store the Search Engine ID here
            models: ["custom_search_engine_id"],
            modelsFetching: false
        ),
    ]

    static let apiTypes = ["chatgpt", "ollama", "claude", "xai", "gemini", "perplexity", "deepseek", "openrouter", "googlesearch"]
    static let newChatNotification = Notification.Name("newChatNotification")
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
