import io
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from server import handler
from pathlib import Path
from server import Service, BUDGET, DAY
import feed

NOW = 1_789_500_000

def game(status='Q3', gid=1):
    return dict(id=gid, season=2026, week=1, kickoff=NOW-6000, status=status, timer='04:32',
                home='DAL', away='NYG', homeID=29, awayID=4, homeScore=20, awayScore=14)

class Response(io.BytesIO):
    def __init__(self, value, headers=None):
        super().__init__(json.dumps({'errors': [], 'response': value}).encode())
        self.headers = headers or {}

class Provider:
    def __init__(self):
        self.calls = 0
        self.value = []
        self.headers = {}
        self.failure = None
        self.gate = None
    def open(self, request, timeout):
        self.calls += 1
        if self.gate:
            self.gate.wait(2)
        if self.failure:
            raise self.failure
        return Response(self.value, self.headers)

class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'cache.db'
        self.now = NOW
        self.provider = Provider()
        self.service = Service(self.path, 'synthetic-key', clock=lambda: self.now, opener=self.provider)
    def tearDown(self):
        self.service.db.close()
        self.temp.cleanup()
    def cached(self, key, value, fetched=None):
        self.service.db.execute('INSERT OR REPLACE INTO cache VALUES (?,?,?)', (key, json.dumps(value), self.now if fetched is None else fetched))
        self.service.db.commit()
    def fetch(self):
        return self.service.fetch('probe', 'games', {'league':1,'season':2026}, lambda rows: rows)
    def test_readers_never_call_provider_and_return_cache_during_slow_fetch(self):
        self.cached('games', [game()])
        self.provider.gate = threading.Event()
        thread = threading.Thread(target=self.fetch)
        thread.start()
        for _ in range(100):
            result = self.service.snapshot(1)
            self.assertEqual(result['games'][0]['homeScore'], 20)
        self.provider.gate.set(); thread.join()
        self.assertEqual(self.provider.calls, 1)
    def test_no_user_count_multiplier_and_demand_expires(self):
        for _ in range(1000): self.service.snapshot(1)
        self.assertEqual(self.provider.calls, 0)
        self.assertEqual(len(self.service.demand), 1)
        self.now += 301
        self.service.tick()
        self.assertEqual(self.provider.calls, 0)
    def test_budget_survives_failure_restart_and_resets_at_utc_midnight(self):
        self.service.db.execute('INSERT INTO usage VALUES (?,?)', (self.service.day(), BUDGET-1))
        self.service.db.commit()
        self.provider.failure = OSError('network failure')
        self.assertFalse(self.fetch())
        self.assertEqual(self.service.used(), BUDGET)
        self.service.db.close()
        self.service = Service(self.path, 'synthetic-key', clock=lambda: self.now, opener=self.provider)
        self.now += 100
        self.assertFalse(self.fetch())
        self.assertEqual(self.provider.calls, 1)
        self.now = (self.service.day()+1)*DAY+3
        self.provider.failure = None
        self.assertTrue(self.fetch())
        self.assertEqual(self.service.used(), 1)
    def test_provider_headroom_and_minute_quota_stop_additional_requests(self):
        self.provider.headers = {'x-ratelimit-requests-remaining': '500'}
        self.assertTrue(self.fetch())
        self.now += 10
        self.assertFalse(self.fetch())
        self.assertEqual(self.provider.calls, 1)
    def test_minute_limit_and_retry_after_are_honored(self):
        self.provider.failure = urllib.error.HTTPError('https://example.invalid',429,'limited',{'Retry-After':'180'},None)
        self.assertFalse(self.fetch())
        self.now += 179
        self.assertFalse(self.fetch())
        self.assertEqual(self.provider.calls, 1)
        self.now += 2
        self.provider.failure = None
        self.assertTrue(self.fetch())
    def test_errors_back_off_and_keep_original_receipt(self):
        self.cached('games', [game()], self.now-200)
        self.provider.failure = ValueError('bad response')
        self.assertFalse(self.service.fetch('games','games',{},lambda r:r))
        self.assertFalse(self.service.due('games',30))
        old = self.service.snapshot(1)['games'][0]
        self.assertTrue(old['stale'])
        self.assertEqual(old['checkedAt'], self.now-200)
        self.now += 31
        self.assertTrue(self.service.due('games',30))
    def test_budget_reduces_cadence_before_hard_stop(self):
        self.assertEqual(self.service.stats_ttl(game()),60)
        self.service.db.execute('INSERT INTO usage VALUES (?,?)',(self.service.day(),5500)); self.service.db.commit()
        self.assertEqual(self.service.stats_ttl(game()),240)
        self.assertEqual(self.service.schedule_ttl([game()]),120)
    def test_final_transition_fetches_final_box_and_keeps_zeros_nulls(self):
        g=game('FT')
        self.cached('coverage',{'players':True}); self.cached('games',[g])
        self.cached('box-1',{'phase':'Q4','players':[]})
        for tid in (29,4): self.cached('roster-'+str(tid),{})
        self.service.snapshot(1)
        self.service.tick()
        self.assertEqual(self.provider.calls,1)
        self.assertEqual(self.service.get('box-1')[0]['phase'],'FT')
    def test_viewed_team_box_is_prioritized_before_unrelated_finals(self):
        other=game('FT',2); other.update(home='BUF',away='NYJ',homeID=20,awayID=21)
        self.cached('coverage',{'players':True}); self.cached('games',[other,game('FT')])
        self.service.snapshot(1,['DAL'])
        self.service.tick()
        self.assertIsNotNone(self.service.get('box-1')[0])
        self.assertIsNone(self.service.get('box-2')[0])
    def test_minute_remaining_header_pauses_without_losing_cache(self):
        self.provider.headers={'X-RateLimit-Remaining':'2'}
        self.assertTrue(self.fetch())
        self.now += 59
        self.assertFalse(self.fetch())
        self.now += 2
        self.assertTrue(self.fetch())
    def test_http_requires_app_header_and_does_not_allow_proxy_parameters(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.service))
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        root='http://127.0.0.1:'+str(server.server_port)
        try:
            for path, headers, code in [('/v1/status',{},403),
                    ('/v1/status',{'X-Blitz-NFL':'1','Origin':'https://example.com'},403),
                    ('/v1/seasons/2025/weeks/1',{'X-Blitz-NFL':'1'},404),
                    ('/v1/seasons/2026/weeks/1?force=1',{'X-Blitz-NFL':'1'},404)]:
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(urllib.request.Request(root+path,headers=headers))
                self.assertEqual(error.exception.code,code)
            with urllib.request.urlopen(urllib.request.Request(root+'/v1/seasons/2026/weeks/1',headers={'X-Blitz-NFL':'1'})) as response:
                body=json.load(response)
            self.assertTrue(body['warming']); self.assertEqual(self.provider.calls,0)
            self.assertNotIn('synthetic-key',json.dumps(body))
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_final_corrections_and_game_day_envelope(self):
        self.assertEqual(self.service.stats_ttl(game('FT')),300)
        # 16 four-hour games plus 14 hours of the shared 30-second scoreboard,
        # 10 idle scoreboard hours, rosters, coverage, final transitions and
        # two hours of five-minute final corrections. Slowdown begins at 5,000.
        expected = 16*4*60 + 14*120 + 10*4 + 32 + 1 + 16 + 16*2*12
        self.assertLess(expected, BUDGET)
    def test_only_active_statuses_use_fast_player_polling(self):
        self.cached('coverage',{'players':True})
        for status in feed.LIVE:
            g=game(status)
            self.cached('games',[g]); self.cached('box-1',{'phase':status,'players':[]},self.now-61)
            for tid in (29,4): self.cached('roster-'+str(tid),{})
            self.service.snapshot(1); before=self.provider.calls
            self.service.tick()
            self.assertEqual(self.provider.calls,before+1,status)
            self.now += 3
        for status in ['NS','PST','CANC','SUSP','INT']:
            self.cached('games',[game(status)])
            self.service.snapshot(1); before=self.provider.calls
            self.service.tick()
            self.assertEqual(self.provider.calls,before,status)
    def test_final_box_is_reused_between_correction_checks(self):
        self.cached('coverage',{'players':True}); self.cached('games',[game('FT')])
        self.cached('box-1',{'phase':'FT','players':[]},self.now-61)
        for tid in (29,4): self.cached('roster-'+str(tid),{},self.now-2*DAY)
        for _ in range(100):
            self.service.snapshot(1); self.service.tick()
        self.assertEqual(self.provider.calls,0)
        self.assertEqual(self.service.snapshot(1)['games'][0]['statsCheckedAt'],self.now-61)
        self.now += 240
        self.cached('games',[game('FT')])
        self.service.snapshot(1); self.service.tick()
        self.assertEqual(self.provider.calls,1)
    def test_kickoff_discovery_does_not_fetch_player_stats_or_speed_up_history(self):
        upcoming=game('NS'); upcoming['kickoff']=self.now+60
        self.cached('coverage',{'players':True}); self.cached('games',[upcoming])
        self.service.snapshot(1)
        self.assertEqual(self.service.schedule_ttl([upcoming]),30)
        self.service.tick()
        self.assertEqual(self.provider.calls,0)
        other_week=game(); other_week['week']=2
        self.assertEqual(self.service.schedule_ttl([game('FT'),other_week]),900)
    def test_archive_boundary_gets_one_last_box_then_uses_cache_across_restart(self):
        g=game('FT'); self.now=g['kickoff']+7*DAY+1
        self.cached('coverage',{'players':True}); self.cached('games',[g])
        self.cached('box-1',{'phase':'FT','players':[]},self.now-2*DAY)
        for tid in (29,4): self.cached('roster-'+str(tid),{},self.now-10*DAY)
        self.service.snapshot(1); self.service.tick()
        self.assertEqual(self.provider.calls,1)
        saved=self.service.get('box-1')[1]
        self.service.db.close()
        self.service=Service(self.path,'synthetic-key',clock=lambda:self.now,opener=self.provider)
        self.now += 30*DAY
        self.cached('coverage',{'players':True}); self.cached('games',[g])
        for _ in range(100): self.service.snapshot(1); self.service.tick()
        self.assertEqual(self.provider.calls,1)
        snapshot=self.service.snapshot(1)['games'][0]
        self.assertEqual(snapshot['statsCheckedAt'],saved)
        self.assertFalse(snapshot['statsStale'])
    def test_cold_historical_box_is_fetched_once_not_left_empty(self):
        g=game('FT'); self.now=g['kickoff']+30*DAY
        self.cached('coverage',{'players':True}); self.cached('games',[g])
        for tid in (29,4): self.cached('roster-'+str(tid),{})
        self.service.snapshot(1); self.service.tick()
        self.assertEqual(self.provider.calls,1)
        self.now += 3
        self.service.tick()
        self.assertEqual(self.provider.calls,1)
    def test_final_identity_does_not_expire_with_live_roster_age(self):
        self.cached('games',[game('FT')])
        self.cached('box-1',{'phase':'FT','players':[dict(providerID=2076,name='Dak Prescott',team='DAL',groups=[])]})
        self.cached('roster-29',{'2076':dict(name='Dak Prescott',position='QB')},self.now-30*DAY)
        self.assertEqual(self.service.snapshot(1)['games'][0]['players'][0]['position'],'QB')
        self.cached('games',[game()])
        self.assertIsNone(self.service.snapshot(1)['games'][0]['players'][0]['position'])
    def test_profile_must_agree_with_box_before_position_is_attached(self):
        self.cached('games',[game()])
        self.cached('box-1',{'phase':'Q3','players':[dict(providerID=2076,name='Dak Prescott',team='DAL',groups=[])]})
        self.cached('roster-29',{'2076':dict(name='Different Person',position='QB')})
        self.assertIsNone(self.service.snapshot(1)['games'][0]['players'][0]['position'])
    def test_cam_translation_uses_existing_cache_and_preserves_name_stats_and_receipt(self):
        self.cached('games',[game('FT')])
        player=dict(providerID=31107,name='Cameron Skattebo',team='NYG',groups=[dict(name='Rushing',stats=[dict(name='yards',value='81'),dict(name='rushing touch downs',value='1')])])
        self.cached('box-1',dict(phase='FT',players=[player]),self.now-60)
        self.cached('roster-4',{'31107':dict(name='Cameron Skattebo',position='RB')})
        result=self.service.snapshot(1)['games'][0]
        self.assertEqual(result['players'][0],dict(player,position='RB',mflID='17045',mflName='Cam Skattebo'))
        self.assertEqual(result['statsCheckedAt'],self.now-60)
        self.assertEqual(self.provider.calls,0)
        self.cached('roster-4',{'31107':dict(name='Different Person',position='RB')})
        self.assertNotIn('mflID',self.service.snapshot(1)['games'][0]['players'][0])
    def test_snapshot_keeps_box_receipt_separate_from_score_receipt(self):
        self.cached('games',[game()])
        self.cached('box-1',{'phase':'Q3','players':[]},self.now-200)
        value=self.service.snapshot(1)['games'][0]
        self.assertFalse(value['stale']); self.assertTrue(value['statsStale'])
        self.assertEqual(value['statsCheckedAt'],self.now-200)

class NormalizationTests(unittest.TestCase):
    def raw(self, stage='Regular Season'):
        return {'league':{'id':1,'season':'2026'},'game':{'id':1,'stage':stage,'week':'Week 1',
            'date':{'timestamp':NOW},'status':{'short':'HT','timer':None}},
            'teams':{'home':{'id':29,'name':'Dallas Cowboys'},'away':{'id':4,'name':'New York Giants'}},
            'scores':{'home':{'total':0},'away':{'total':None}}}
    def test_unresolved_postseason_does_not_break_regular_season(self):
        placeholder=self.raw('Post Season'); placeholder['teams']={'home':{'id':0},'away':{'id':0}}
        result=feed.games([placeholder,self.raw()],2026)
        self.assertEqual(len(result),1); self.assertEqual(result[0]['status'],'HT')
        self.assertEqual(result[0]['homeScore'],0); self.assertIsNone(result[0]['awayScore'])
    def test_wrong_league_duplicate_game_and_unresolved_regular_fixture_fail(self):
        bad=self.raw(); bad['league']['id']=2
        with self.assertRaises(ValueError): feed.games([bad],2026)
        with self.assertRaises(ValueError): feed.games([self.raw(),self.raw()],2026)
        bad=self.raw(); bad['teams']['home']['id']=0
        with self.assertRaises(ValueError): feed.games([bad],2026)
    def test_null_overtime_code_is_final_not_live(self):
        row=self.raw(); row['game']['status']={'short':None,'long':'Final/OT','timer':None}
        self.assertEqual(feed.games([row],2026)[0]['status'],'AOT')
    def test_cross_team_player_collision_is_rejected(self):
        def row(tid):
            return {'team':{'id':tid},'groups':[{'name':'Passing','players':[{'player':{'id':99,'name':'Same'},'statistics':[]}]}]}
        with self.assertRaises(ValueError): feed.players([row(29),row(4)],game())
    def test_null_zero_and_composite_stats_are_preserved(self):
        rows=[{'team':{'id':29},'groups':[{'name':'Passing','players':[{'player':{'id':99,'name':'Same'},
            'statistics':[{'name':'TD','value':0},{'name':'comp att','value':'22/34'},{'name':'missing','value':None}]}]}]}]
        stats=feed.players(rows,game())[0]['groups'][0]['stats']
        self.assertEqual([s['value'] for s in stats],['0','22/34',None])

if __name__ == '__main__': unittest.main()
