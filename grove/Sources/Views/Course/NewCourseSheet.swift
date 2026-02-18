import SwiftUI
import SwiftData

struct NewCourseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var sourceURL = ""
    @State private var description = ""

    let onCreate: (Course) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Course")
                    .font(.groveItemTitle)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Course Title") {
                    TextField("e.g., MIT 6.824 Distributed Systems", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Description (optional)") {
                    TextField("What this course covers", text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Source URL (optional)") {
                    TextField("https://youtube.com/playlist?list=... or course page", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createCourse()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 360)
    }

    private func createCourse() {
        let courseTitle = title.trimmingCharacters(in: .whitespaces)
        guard !courseTitle.isEmpty else { return }

        let course = Course(title: courseTitle)
        if !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty {
            course.sourceURL = sourceURL.trimmingCharacters(in: .whitespaces)
        }
        if !description.trimmingCharacters(in: .whitespaces).isEmpty {
            course.courseDescription = description.trimmingCharacters(in: .whitespaces)
        }

        modelContext.insert(course)
        try? modelContext.save()

        onCreate(course)
        dismiss()
    }
}
