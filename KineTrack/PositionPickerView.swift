//
//  PositionPickerView.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

import SwiftUI

struct PositionPickerView: View {
    @Binding var selectedPosition: Position?
    
    var body: some View {
        List(Position.allPositions) { position in
            Button {
                selectedPosition = position
            } label: {
                HStack {
                    Image(systemName: position.icon)
                        .foregroundColor(.blue)
                        .frame(width: 30)
                    
                    Text(position.name)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if selectedPosition?.id == position.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
            .contentShape(Rectangle())
        }
    }
}
