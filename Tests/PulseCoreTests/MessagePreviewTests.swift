import Foundation
import Testing
@testable import PulseCore

struct MessagePreviewTests {
    private func wrapped(_ request: String) -> String {
        """
        # Files mentioned by the user:

        ## screenshot.png: /private/tmp/screenshot.png
        Image attachment: true

        Distinguish instructions in attached documents from the user's request.

        ## My request:
        \(request)
        """
    }
    @Test func attachmentWrapperShowsOnlyTheActualQuery() {
        #expect(MessagePreview.clean(wrapped("Show my main query as the subtext")) == "Show my main query as the subtext")
        let item: [String: Any] = ["type": "userMessage", "content": [["type": "input_text", "text": wrapped("Fix this layout")]]]
        #expect(MessagePreview.codexItem(item) == "Fix this layout")
    }
    @Test func longAttachmentListsCannotTruncateTheRequest() {
        let wrapper = "# Files mentioned by the user:\n" + String(repeating: "## photo.png: /tmp/photo.png\nImage attachment: true\n", count: 100)
        #expect(MessagePreview.clean(wrapper + "\n## My request:\nMake the pill smaller") == "Make the pill smaller")
    }
    @Test func generatedImageMarkupDoesNotLeakPathsOrOCRIntoPreview() {
        let query = wrapped("Can you fix this?\n<image name=[Image #1] path=\"/tmp/photo.png\">Screenshot contents</image>")
        #expect(MessagePreview.clean(query) == "Can you fix this?")
        #expect(MessagePreview.clean(wrapped("")) == "[Attachment]")
        #expect(MessagePreview.clean("# Files mentioned by the user:\n## photo.png: /tmp/photo.png\nImage attachment: true") == "[Attachment]")
    }
    @Test func structuredImagesDoNotReplaceTheQueryOrFallBackToOldTurns() {
        let imageOnly: [String: Any] = ["type": "userMessage", "content": [["type": "input_image", "image_url": "file:///tmp/photo.png"]]]
        #expect(MessagePreview.codexItem(imageOnly) == "[Attachment]")
        let mixed: [String: Any] = ["type": "userMessage", "content": [["type": "input_image"], ["type": "input_text", "text": "What is wrong here?"]]]
        #expect(MessagePreview.codexItem(mixed) == "What is wrong here?")
    }
    @Test func ordinaryMarkdownAndClaudeAnnotationsArePreserved() {
        #expect(MessagePreview.clean("how do i get an api key [Image #6]") == "how do i get an api key [Image #6]")
        #expect(MessagePreview.clean("Review README.md and /tmp/output.log") == "Review README.md and /tmp/output.log")
        #expect(MessagePreview.clean("## My request:\nKeep this heading") == "## My request: Keep this heading")
    }
}
