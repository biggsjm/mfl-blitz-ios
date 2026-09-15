import Foundation
import Testing
import MFLCore
@testable import MFLBlitz

struct GameDayEnhancementTests {
    @Test func decodesActualMFLRuleEnvelope() throws {
        let raw = #"{"rules":{"positionRules":{"positions":"QB|RB|WR|TE","rule":[{"event":{"$t":"CY"},"range":{"$t":"0-999"},"points":{"$t":"1/15"}}]}}}"#
        let metadata = #"{"allRules":{"rule":[{"abbreviation":{"$t":"CY"},"shortDescription":{"$t":"Receiving yards"}}]}}"#
        let rules=try MFLScoringRule.decode(JSONDecoder().decode(MFLJSONValue.self,from:Data(raw.utf8)),descriptions:JSONDecoder().decode(MFLJSONValue.self,from:Data(metadata.utf8)))
        #expect(rules.count==1);#expect(rules[0].label=="Receiving yards")
        #expect(rules[0].calculate(value:23)==1);#expect(!rules[0].applies(to:"DEF"))
    }
    @Test func strangePointsUseLeagueYardageAndTouchdown() {
        let player=NFLFeedPreview.make().games[1].players[0]
        let result=ScoringBreakdown(rules:ScoringBreakdown.previewRules,position:"TE",player:player,official:9)
        #expect(result.total==9);#expect(result.difference==0)
        #expect(result.contributions.map(\.rule.event)==["CY","CC","#C"])
        #expect(result.contributions.map(\.points)==[1,2,6])
    }
    @Test func completionPointsAndPenaltiesExplainDak() {
        let player=NFLFeedPlayer(providerID:1,name:"Dak Prescott",team:"DAL",position:"QB",groups:[
            .init(name:"Passing",stats:[.init(name:"comp att",value:"22/32"),.init(name:"yards",value:"175"),.init(name:"passing touch downs",value:"2"),.init(name:"interceptions",value:"1")]),
            .init(name:"Rushing",stats:[.init(name:"yards",value:"14")])])
        let result=ScoringBreakdown(rules:ScoringBreakdown.previewRules,position:"QB",player:player,official:25)
        #expect(result.total==25);#expect(result.difference==0)
        let missing=ScoringBreakdown(rules:ScoringBreakdown.previewRules,position:"QB",player:nil,official:25)
        #expect(missing.contributions.isEmpty);#expect(missing.difference==25)
    }
    @Test func unsupportedRulesMissingTDAndAdjustmentStayVisible() {
        var player=NFLFeedPreview.make().games[1].players[0]
        player=NFLFeedPlayer(providerID:player.id,name:player.name,team:player.team,position:player.position,groups:[.init(name:"Receiving",stats:[.init(name:"total receptions",value:"2"),.init(name:"yards",value:"23")])])
        let result=ScoringBreakdown(rules:ScoringBreakdown.previewRules,position:"TE",player:player,official:9)
        #expect(result.total==3);#expect(result.difference==6)
        #expect(result.remaining.contains { $0.rule.event=="#C" && $0.points==nil })
        let threshold=MFLScoringRule(id:20,positions:["TE"],event:"CY",label:"Threshold",range:"0-999",points:"1/15",thresholdPoints:"0")
        #expect(threshold.calculate(value:23)==nil)
        for expression in ["1/0","*6junk","1;2","1/10/2","NaN"] {
            let rule=MFLScoringRule(id:21,positions:["QB"],event:"PY",label:"Test",range:"0-999",points:expression)
            #expect(rule.calculate(value:100)==nil)
        }
    }
    @Test func defenseIdentityAndReceiptAreSeparateFromIndividualStats() throws {
        var feed=NFLFeedPreview.make();var game=feed.games[0]
        let defense=NFLFeedPlayer(providerID:29,name:"Dallas Cowboys",team:"DAL",position:"DEF",groups:[.init(name:"Team defense",stats:[.init(name:"SK",value:"5"),.init(name:"IC",value:"1"),.init(name:"TPA",value:"14")])])
        game.defenses=[defense];game.defenseCheckedAt=Date().timeIntervalSince1970-400;game.defenseStale=false
        let player=MatchupPlayer(id:"defense",name:"Dallas",position:"DF",nflTeam:"DAL",livePoints:9,lineupStatus:.starter,gameSecondsRemaining:1000,statLine:nil)
        #expect(game.player(matching:player)==defense)
        #expect(game.statsAreStale(for:player));#expect(!game.statsAreStale())
        #expect(defense.summary=="5 sacks · 1 INT · 14 points allowed")
        #expect(ScoringBreakdown.stats(defense)["TPA"]==14)
        #expect(ScoringBreakdown.stats(defense)["OPA"]==nil)
        feed.games[0]=game;_ = try feed.validated(season:2026,week:1)
        feed.games[0].defenses=[defense,defense]
        #expect(throws:(any Error).self) { try feed.validated(season:2026,week:1) }
    }
    @MainActor @Test func backgroundHistoryReplacesAggregateReopenDeltaButKeepsRealGaps() {
        func event(_ id:String,_ at:Double,_ kind:String,_ source:String,from:Double? = nil) -> MatchupTimelineEvent {
            .init(id:id,at:at,kind:kind,name:"Score",teamID:"0001",previous:3,current:25,source:source,fromAt:from)
        }
        let local=event("local",1000,"team","app",from:100)
        var a=event("a",200,"team","background");a.current=10
        var b=event("b",800,"team","background");b.previous=10
        let history=[event("tracking",50,"tracking","background"),a,b]
        let response=MatchupTimelineResponse(schema:1,season:2026,leagueID:"12345",week:1,teamIDs:["0001","0002"],checkedAt:1100,events:history)
        #expect(MatchupTimelineStore.localEventsToKeep([local],response:response).isEmpty)
        let gap=MatchupTimelineResponse(schema:1,season:2026,leagueID:"12345",week:1,teamIDs:["0001","0002"],checkedAt:1100,events:history+[event("gap",900,"gap","background")])
        #expect(MatchupTimelineStore.localEventsToKeep([local],response:gap)==[local])
    }
    @Test func alertDefaultsAndLinksAreScoped() {
        #expect(!LineupAlertOptions().enabled)
        let link=LeagueDeepLink(URL(string:"mflblitz://lineup?scope=2026.41333.0001&id=lineup&week=1")!)
        #expect(link?.destination == .lineup(week:1))
        #expect(LeagueDeepLink(URL(string:"mflblitz://lineup?scope=2026.41333.0001&id=lineup&week=99")!)==nil)
    }
    @MainActor @Test func timelineSurvivesRestartAndKeepsCorrectionAndGap() async throws {
        let path=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:path) }
        let disk=MatchupTimelineDisk(url:path),store=MatchupTimelineStore(disk:disk)
        var scores=SampleData.scores
        let now=Date();scores.checkedAt=now
        await store.observe(scores,scope:"one",persist:true,now:now)
        scores.checkedAt=now.addingTimeInterval(300)
        scores.matchups[0].away.score=(scores.matchups[0].away.reportedScore ?? 0)-2
        await store.observe(scores,scope:"one",persist:true,now:now.addingTimeInterval(300))
        let events=store.events(scope:"one",week:scores.week,matchup:scores.matchups[0])
        #expect(events.contains { $0.kind=="gap" })
        #expect(events.contains { $0.kind=="team" && ($0.current ?? 0)-($0.previous ?? 0)==(-2) })
        let saved=await disk.load(scope:"one")
        #expect(saved?.events.values.flatMap { $0 }.contains { $0.kind=="gap" }==true)
        #expect(await disk.load(scope:"different")==nil)
        await store.clear();#expect(!FileManager.default.fileExists(atPath:path.path))
    }
}
