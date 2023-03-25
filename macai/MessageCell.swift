//
//  MessageCell.swift
//  macai
//
//  Created by Renat Notfullin on 25.03.2023.
//

import SwiftUI

struct MessageCell: View {
    @ObservedObject var chat: ChatEntity
    @State var timestamp: Date
    @Binding var message: String
    @Binding var isActive: Bool

    var body: some View {
        NavigationLink(destination: ChatView(chat: chat, message: chat.newMessage), isActive: $isActive) {
            VStack(alignment: .leading) {

                Text(timestamp, style: .date)
                    .font(.caption)

                // Show last message as truncated text
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct MessageCell_Previews: PreviewProvider {

    static var previews: some View {
        let chat = ChatEntity(context: PersistenceController.shared.container.viewContext)

        MessageCell(
            chat: chat,
            timestamp: Date(),
            message: .constant("Hello, how are you?"),
            isActive: .constant(false)
        )
        .previewLayout(.sizeThatFits)
    }
}
