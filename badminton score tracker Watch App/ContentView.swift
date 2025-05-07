//
//  ContentView.swift
//  badminton score tracker watch Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI
import WatchKit

struct ContentView: View {
    @State private var myScore = 0
    @State private var opponentScore = 0
    @State private var isAnimating = false
    @State private var winner: String? = nil
    
    func checkWinner() {
        // Check if either player has won
        let hasWon = (myScore >= 21 && myScore - opponentScore >= 2) || // I won
                     (opponentScore >= 21 && opponentScore - myScore >= 2) // Opponent won
        
        if hasWon {
            winner = myScore > opponentScore ? "Me" : "Opponent"
            isAnimating = true
            
            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                myScore = 0
                opponentScore = 0
                isAnimating = false
                winner = nil
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Court Background
                Color(red: 0.2, green: 0.6, blue: 0.2) // Badminton court green
                    .ignoresSafeArea()
                
                // Court Lines
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 2)
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 2)
                }
                .padding(.horizontal, 12)
                
                // Main Content
                VStack(spacing: 8) {
                    // Opponent's Score (Top)
                    VStack(spacing: 4) {
                        Text("Opponent")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text("\(opponentScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.25))
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        opponentScore += 1
                        checkWinner()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                myScore = 0
                                opponentScore = 0
                                winner = nil
                            }
                    )
                    .scaleEffect(winner == "Opponent" && isAnimating ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                    
                    // My Score (Bottom)
                    VStack(spacing: 4) {
                        Text("Me")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text("\(myScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.25))
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        myScore += 1
                        checkWinner()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                myScore = 0
                                opponentScore = 0
                                winner = nil
                            }
                    )
                    .scaleEffect(winner == "Me" && isAnimating ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                }
                .padding(.horizontal, 16)
                
                // Winner Overlay
                if isAnimating {
                    Text("\(winner == "Me" ? "I Win!" : "\(winner ?? "") Wins!")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
