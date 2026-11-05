import AppKit
import Vision
// 그림에서 글자를 읽어(Vision) 한글이 있는 줄을 출력한다. 하나라도 있으면 실패
// 사용법: xcrun swift scripts/find-hangul.swift <png>...
var found = false
for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.recognitionLevel = .accurate
    try? VNImageRequestHandler(cgImage: cg).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    // 언어 고르기의 "한국어"는 그 언어로 쓰는 게 맞아서 뺀다
    let hangul = lines.filter { $0.range(of: "[가-힣]", options: .regularExpression) != nil && !$0.contains("한국어") }
    if !hangul.isEmpty { found = true }
    print((path as NSString).lastPathComponent, "줄 \(lines.count)", hangul.isEmpty ? "한글 없음" : "한글: \(hangul)")
}
exit(found ? 1 : 0)
