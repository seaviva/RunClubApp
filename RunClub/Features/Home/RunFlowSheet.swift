//
//  RunFlowSheet.swift
//  RunClub
//
//  Wraps RunSetupSheet and RunPreviewSheet in a single sheet container
//  to enable smooth transitions between steps without sheet close/reopen.

import SwiftUI

struct RunFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    // Initial values passed from HomeView
    let initialTemplate: RunTemplateType
    let initialMinutes: Int
    let initialGenres: Set<Genre>
    let initialDecades: Set<Decade>
    
    // Callback when user confirms and starts the run
    let onConfirm: (PreviewRun) -> Void
    
    // Internal navigation state
    @State private var currentStep: FlowStep = .setup
    
    // Values captured from setup step
    @State private var selectedTemplate: RunTemplateType
    @State private var selectedMinutes: Int
    @State private var selectedGenres: Set<Genre>
    @State private var selectedDecades: Set<Decade>
    
    enum FlowStep {
        case setup
        case preview
    }
    
    init(
        initialTemplate: RunTemplateType = .light,
        initialMinutes: Int = 30,
        initialGenres: Set<Genre> = [],
        initialDecades: Set<Decade> = [],
        onConfirm: @escaping (PreviewRun) -> Void
    ) {
        self.initialTemplate = initialTemplate
        self.initialMinutes = initialMinutes
        self.initialGenres = initialGenres
        self.initialDecades = initialDecades
        self.onConfirm = onConfirm
        
        // Initialize state with initial values
        _selectedTemplate = State(initialValue: initialTemplate)
        _selectedMinutes = State(initialValue: initialMinutes)
        _selectedGenres = State(initialValue: initialGenres)
        _selectedDecades = State(initialValue: initialDecades)
    }
    
    var body: some View {
        ZStack {
            // Show setup or preview based on current step
            switch currentStep {
            case .setup:
                RunSetupSheet(
                    initialTemplate: selectedTemplate,
                    initialMinutes: selectedMinutes,
                    initialGenres: selectedGenres,
                    initialDecades: selectedDecades
                ) { template, minutes, genres, decades in
                    // Capture values and move to preview
                    selectedTemplate = template
                    selectedMinutes = minutes
                    selectedGenres = genres
                    selectedDecades = decades
                    
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = .preview
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
            case .preview:
                RunPreviewSheet(
                    template: selectedTemplate,
                    runMinutes: selectedMinutes,
                    genres: Array(selectedGenres),
                    decades: Array(selectedDecades),
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStep = .setup
                        }
                    },
                    onContinue: { preview in
                        onConfirm(preview)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
    }
}

