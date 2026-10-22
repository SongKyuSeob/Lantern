// swift-tools-version: 6.2
import PackageDescription

// UI와 무관한 로직(깨어 있기 세션, 전원 상태 판단, 안전장치, 할 일 저장소)을 담는다.
// AppKit 의존은 앱 타깃에만 두고, 나중에 iOS 앱에서도 재사용할 수 있게 유지한다.
let package = Package(
    name: "LanternKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LanternKit", targets: ["LanternKit"]),
    ],
    targets: [
        .target(name: "LanternKit"),
        .testTarget(name: "LanternKitTests", dependencies: ["LanternKit"]),
    ]
)
