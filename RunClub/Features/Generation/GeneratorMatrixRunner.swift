//
//  GeneratorMatrixRunner.swift
//  RunClub
//
//  Developer utility to dry-run all templates × durations against the
//  current SwiftData cache and print a consolidated validation report.
//

import Foundation

final class GeneratorMatrixRunner {
    private struct StubSpotify: Sendable {
        let service = SpotifyService()
        func market() async -> String { "US" }
        func playableIds(for ids: [String]) async -> Set<String> { Set(ids) }
    }

    func runAll(with generator: LocalGenerator, verbose: Bool = false) async {
        let stub = StubSpotify()
        var failures: [String] = []
        var rows: [String] = []
        for template in RunTemplateType.allCases {
            let minutes = 40
            do {
                let res = try await generator.generateDryRun(template: template,
                                                             runMinutes: minutes,
                                                             genres: [],
                                                             decades: [],
                                                             spotify: stub.service)
                // Checks
                if !(res.totalSeconds >= res.minSeconds && res.totalSeconds <= res.maxSeconds) {
                    failures.append("bounds \(template.rawValue)-\(minutes) secs=\(res.totalSeconds) range=[\(res.minSeconds),\(res.maxSeconds)]")
                }
                var capOk = true
                var backToBackOk = true
                var perArtist: [String: Int] = [:]
                for (i, aid) in res.artistIds.enumerated() {
                    perArtist[aid, default: 0] += 1
                    if i > 0 && res.artistIds[i-1] == aid { backToBackOk = false }
                }
                if perArtist.values.contains(where: { $0 > 2 }) { capOk = false }
                let maxCount = res.efforts.filter { $0 == .max }.count
                let hardCount = res.efforts.filter { $0 == .hard }.count
                if maxCount > 1 { failures.append("max-cap \(template.rawValue)-\(minutes) max=\(maxCount)") }
                if template == .kicker && hardCount > 2 { failures.append("kicker-hard-cap \(minutes) hard=\(hardCount)") }
                if !capOk { failures.append("artist-cap \(template.rawValue)-\(minutes)") }
                if !backToBackOk { failures.append("back-to-back \(template.rawValue)-\(minutes)") }
                // Source mix
                var likes = 0, recs = 0, third = 0
                for s in res.sources {
                    switch s {
                    case .likes: likes += 1
                    case .recs: recs += 1
                    case .third: third += 1
                    }
                }
                rows.append("\(template.rawValue),\(minutes),\(res.trackIds.count),\(res.totalSeconds),\(likes),\(recs),\(third)")
                if verbose {
                    if let metrics = res.debugLines.first(where: { $0.contains("LocalGen metrics") }) {
                        print(metrics)
                    }
                }
            } catch {
                failures.append("exception \(template.rawValue)-\(minutes): \(error)")
            }
        }
        print("GeneratorMatrix: template,duration,tracks,seconds,likes,recs,third")
        for r in rows { print(r) }
        if failures.isEmpty {
            print("GeneratorMatrix: ALL OK")
        } else {
            print("GeneratorMatrix FAILURES (\(failures.count)):")
            for f in failures { print(" - \(f)") }
        }
    }
}


