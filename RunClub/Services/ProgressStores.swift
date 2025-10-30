//
//  ProgressStores.swift
//  RunClub
//
//  Thin typed wrappers so we can inject two distinct progress stores via Environment.
//

import Foundation

final class LikesProgressStore: CrawlProgressStore {}
final class RecsProgressStore: CrawlProgressStore {}


