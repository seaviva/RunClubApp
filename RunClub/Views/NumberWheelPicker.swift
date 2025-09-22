//
//  NumberWheelPicker.swift
//  RunClub
//
//  Simple UIKit-backed wheel picker for integer values, allowing custom row height and font.
//

import SwiftUI
import UIKit

struct NumberWheelPicker: UIViewRepresentable {
    @Binding var selection: Int
    let values: [Int]
    let rowHeight: CGFloat
    let fontSize: CGFloat
    let textColor: UIColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        if let index = values.firstIndex(of: selection) {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        if let index = values.firstIndex(of: selection), uiView.selectedRow(inComponent: 0) != index {
            uiView.selectRow(index, inComponent: 0, animated: true)
        }
        uiView.reloadAllComponents()
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        let parent: NumberWheelPicker
        private lazy var font: UIFont = {
            if let f = UIFont(name: "SuisseIntl-Medium", size: parent.fontSize) { return f }
            return UIFont.systemFont(ofSize: parent.fontSize, weight: .medium)
        }()

        init(_ parent: NumberWheelPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { parent.values.count }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            parent.rowHeight
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard row >= 0 && row < parent.values.count else { return }
            parent.selection = parent.values[row]
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label: UILabel
            if let lbl = view as? UILabel { label = lbl } else { label = UILabel() }
            label.textAlignment = .center
            label.font = font
            label.textColor = parent.textColor
            label.text = String(parent.values[row])
            return label
        }
    }
}


