// swift-tools-version:5.9
// SwiftPM-manifest som gjør kjernen (spillmotor, AI, Elo og companion-
// poengføring) byggbar UTEN Xcode – på Linux, Windows (WSL) og macOS.
// iOS-appen bygges fortsatt med XcodeGen/Xcode (project.yml); dette
// manifestet gjenbruker de samme kildefilene og legger til et
// kommandolinjeverktøy for å se MesterAI i aksjon i terminalen.
//
//   swift test                        – motor-, AI- og companion-tester
//   swift run -c release Amerikaneren – MesterAI-demo m.m. (se `hjelp`)
//
// Alt ligger i én modul ved navn `Amerikaneren`, slik at testene kan
// bruke `@testable import Amerikaneren` både her og i Xcode-prosjektet.
import PackageDescription

let package = Package(
    name: "Amerikaneren",
    targets: [
        .executableTarget(
            name: "Amerikaneren",
            path: ".",
            exclude: [
                "README.md",
                "docs",
                "project.yml",
                "Tests",
                "Amerikaneren/App",
                "Amerikaneren/Game",
                "Amerikaneren/Online",
                "Amerikaneren/Stats",
                "Amerikaneren/Theme",
                "Amerikaneren/Opponents",
                "Amerikaneren/Campaign",
                "Amerikaneren/Onboarding",
                "Amerikaneren/Companion/CompanionView.swift",
                "Amerikaneren/Companion/CompanionViewModel.swift",
            ],
            sources: [
                "Amerikaneren/Engine",
                "Amerikaneren/AI",
                "Amerikaneren/Ranked",
                "Amerikaneren/Companion/CompanionScoring.swift",
                "CLI",
            ]
        ),
        .testTarget(
            name: "AmerikanerenTests",
            dependencies: ["Amerikaneren"],
            path: "Tests"
        ),
    ]
)
