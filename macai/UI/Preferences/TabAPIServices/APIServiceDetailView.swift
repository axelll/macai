//
//  APIServiceDetailView.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//
import SwiftUI

struct APIServiceDetailView: View {
    @StateObject private var viewModel: APIServiceDetailViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        let viewModel = APIServiceDetailViewModel(viewContext: viewContext, apiService: apiService)
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private let types = AppConstants.apiTypes
    @State private var previousModel = ""
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?
    @State private var loadingIconIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Service Name:")
                    .frame(width: 100, alignment: .leading)

                TextField("API Name", text: $viewModel.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            GroupBox {
                VStack {
                    VStack {
                        HStack {
                            Text("API Type:")
                                .frame(width: 100, alignment: .leading)

                            Image("logo_\(viewModel.type)")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .antialiased(true)
                                .frame(width: 14, height: 14)

                            Picker("", selection: $viewModel.type) {
                                ForEach(types, id: \.self) {
                                    Text(AppConstants.defaultApiConfigurations[$0]?.name ?? $0)
                                }
                            }.onChange(of: viewModel.type) { newValue in
                                viewModel.onChangeApiType(newValue)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    HStack {
                        Text("API URL:")
                            .frame(width: 100, alignment: .leading)

                        TextField("Paste your URL here", text: $viewModel.url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            viewModel.url = viewModel.defaultApiConfiguration!.url
                        }) {
                            Text("Default")
                        }
                    }

                    if (viewModel.defaultApiConfiguration?.apiKeyRef ?? "") != "" {
                        HStack {
                            Text("API Token:")
                                .frame(width: 100, alignment: .leading)

                            TextField("Paste your token here", text: $viewModel.apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isFocused)
                                .blur(radius: !viewModel.apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                                .onChange(of: viewModel.apiKey) { newValue in
                                    viewModel.onChangeApiKey(newValue)
                                }
                        }

                        HStack {
                            Spacer()
                            Link(
                                "How to get API Token",
                                destination: URL(
                                    string: viewModel.defaultApiConfiguration!.apiKeyRef
                                )!
                            )
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                    }

                    HStack {
                        Text("LLM Model:")
                            .frame(width: 94, alignment: .leading)

                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(viewModel.availableModels.sorted(), id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                            Text("Enter custom model").tag("custom")
                        }
                        .onChange(of: viewModel.selectedModel) { newValue in
                            if newValue == "custom" {
                                viewModel.isCustomModel = true
                            }
                            else {
                                viewModel.isCustomModel = false
                                viewModel.model = newValue
                            }
                        }
                        .disabled(viewModel.isLoadingModels)

                        if AppConstants.defaultApiConfigurations[viewModel.type]?.modelsFetching ?? false {
                            ButtonWithStatusIndicator(
                                title: "Update",
                                action: { viewModel.onUpdateModelsList() },
                                isLoading: viewModel.isLoadingModels,
                                hasError: viewModel.modelFetchError != nil,
                                errorMessage:
                                    "Can't get models from server (or I don't know how), but don't worry - using default list",
                                successMessage: "Click to refresh models list",
                                isSuccess: !viewModel.isLoadingModels && viewModel.modelFetchError == nil
                                    && viewModel.availableModels.count > 0
                            )
                        }
                    }
                    .padding(.top, 8)

                    if viewModel.isCustomModel {
                        VStack {
                            TextField("Enter custom model name", text: $viewModel.model)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }

                    HStack {
                        Spacer()
                        Link(
                            "Models reference",
                            destination: URL(string: viewModel.defaultApiConfiguration!.apiModelRef)!
                        )
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .padding(.bottom)

                    HStack {
                        ButtonTestApiTokenAndModel(
                            lampColor: $lampColor,
                            gptToken: viewModel.apiKey,
                            gptModel: viewModel.model,
                            apiUrl: viewModel.url,
                            apiType: viewModel.type
                        )
                    }
                }
                .padding(8)
            }

            VStack {
                HStack {
                    // TODO: implement unlimited context size (is it really needed though?)
                    //                    Toggle(isOn: $viewModel.contextSizeUnlimited) {
                    //                        Text("Unlimited context size")
                    //                    }
                    //                    .disabled(true)
                    //                    Spacer()
                }
                if !viewModel.contextSizeUnlimited {
                    HStack {
                        Slider(
                            value: $viewModel.contextSize,
                            in: 5...100,
                            step: 5
                        ) {
                            Text("Context size")
                        } minimumValueLabel: {
                            Text("5")
                        } maximumValueLabel: {
                            Text("100")
                        }
                        .disabled(viewModel.contextSizeUnlimited)

                        Text(String(format: ("%.0f messages"), viewModel.contextSize))
                            .frame(width: 90)
                    }
                }
            }.padding(.top, 16)

            VStack {
                Toggle(isOn: $viewModel.generateChatNames) {
                    HStack {
                        Text("Automatically generate chat names (using selected model)")
                        Button(action: {
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(
                            "Chat name will be generated based on chat messages. Selected model will be used to generate chat name"
                        )

                        Spacer()
                    }
                }
                Toggle(isOn: $viewModel.useStreamResponse) {
                    HStack {
                        Text("Use stream responses")
                        Button(action: {
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(
                            "If on, the ChatGPT response will be streamed to the client. This will allow you to see the response in real-time. If off, the response will be sent to the client only after the model has finished processing."
                        )

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 8)

            HStack {
                Text("Default AI Assistant:")
                    .frame(width: 160, alignment: .leading)

                Picker("", selection: $viewModel.defaultAiPersona) {
                    ForEach(personas) { persona in
                        Text(persona.name ?? "Untitled").tag(persona)
                    }
                }
            }

            if AppConstants.openAiReasoningModels.contains(viewModel.model) {
                Text(
                    "💁‍♂️ OpenAI API doesn't support system message and temperature other than 1 for o1 models. macai will send system message as a user message internally, while temperature will be always set to 1.0"
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            
            if viewModel.type == "googlesearch" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔍 Google Search Integration Setup:")
                            .font(.headline)
                        
                        Text("1. Create a Google Custom Search Engine:")
                            .fontWeight(.medium)
                        Text("• Go to https://programmablesearchengine.google.com/controlpanel/create")
                        Text("• Create a new search engine with \"Search the entire web\" option enabled")
                        Text("• Copy your Search Engine ID (cx parameter)")
                        Text("• Paste it in the \"LLM Model\" field above")
                        
                        Text("2. Get Google API Key:")
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        Text("• Go to https://developers.google.com/custom-search/v1/introduction")
                        Text("• Click \"Get a Key\" and follow the instructions")
                        Text("• Paste the API key in the \"API Token\" field above")
                        
                        Text("3. Using Google Search with ANY LLM:")
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        Text("• You can now use Google Search with any LLM in your chats")
                        Text("• Just include search phrases like \"погугли\", \"google\", \"search for\", etc.")
                        Text("• For example: \"search for latest news about AI\"")
                        Text("• The system will perform a search and send results to your LLM")
                        
                        Text("4. For best results:")
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        Text("• Select the \"Web Searcher\" persona when starting new chats")
                        Text("• This persona is optimized for working with search results")
                    }
                    .padding(8)
                }
                .padding(.vertical, 8)
            }

            HStack {
                if viewModel.apiService != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                }

                Button(action: {
                    viewModel.saveAPIService()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(16)
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.deleteAPIService()
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
