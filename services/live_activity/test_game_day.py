import copy
import json
import tempfile
import unittest
from test_server import CONFIG, NOW, subscription, document, FakeMFL, FakeAPNs
from server import Service
from scoring import read_matchup, updated_state, validate_subscription
from lineup_alerts import candidates
from nfl_context import enrich


def alert_body():
    return dict(season=2026,leagueID='12345',franchiseID='0001',week=1,required=2,
        token='ab'*32,environment='sandbox',options=dict(reminder=False,unavailable=False,incomplete=True),
        players={'10':dict(name='Test Receiver',team='JAC')},revision=1)

def schedule(start=NOW+1200):
    return {'nflSchedule':{'week':'1','matchup':{'kickoff':str(start),'team':[{'id':'JAC'},{'id':'CLE'}]}}}

def injuries(status='Out',at=NOW):
    return {'injuries':{'week':'1','timestamp':str(at),'injury':{'id':'10','status':status}}}

class GameDayTests(unittest.TestCase):
    def test_timeline_quiet_periods_require_confirmed_state_and_same_lineup(self):
        from timeline import needs_gap
        teams = {'one': {'starters': {'1': 5}, 'unknown': []}}
        self.assertFalse(needs_gap({'phase': 'final', 'teams': teams}, teams, {'phase': 'final'}, NOW))
        future = NOW + 3600 - 978307200
        before = {'phase': 'waiting', 'teams': teams, 'nextKickoff': future}
        self.assertFalse(needs_gap(before, teams, {'phase': 'waiting', 'nextKickoff': future}, NOW))
        self.assertTrue(needs_gap(before, teams, {'phase': 'waiting', 'nextKickoff': future}, NOW + 7200))
        self.assertTrue(needs_gap(before, teams, {'phase': 'live'}, NOW))
        self.assertTrue(needs_gap(before, {'one': {'starters': {'2': 5}, 'unknown': []}}, {'phase': 'final'}, NOW))

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.now=NOW
        self.mfl=FakeMFL();self.apns=FakeAPNs()
        self.service=Service(CONFIG,self.temp.name+'/state.db',self.mfl,self.apns,clock=lambda:self.now)
    def tearDown(self):
        self.service.db.close();self.temp.cleanup()
    def test_incomplete_is_independent_and_filled_saved_lineup_stops_warning(self):
        b=alert_body();self.assertEqual(len(candidates(b,document(),schedule(),{},NOW)),1)
        b['required']=1;self.assertEqual(candidates(b,document(),schedule(),{},NOW),[])
        b['required']=2;b['options']['incomplete']=False
        self.assertEqual(candidates(b,document(),schedule(),{},NOW),[])
    def test_no_unknown_empty_wrong_week_or_postkickoff_guess(self):
        b=alert_body()
        for status in ('unknown',None):
            d=document();d['liveScoring']['matchup']['franchise'][0]['players']['player']['status']=status
            self.assertEqual(candidates(b,d,schedule(),{},NOW),[])
        self.assertEqual(candidates(b,document(),schedule(NOW),{},NOW),[])
        self.assertEqual(candidates(b,document(),schedule(NOW+1801),{},NOW),[])
        d=document();d['liveScoring']['week']='2'
        with self.assertRaises(ValueError): candidates(b,d,schedule(),{},NOW)
    def test_unavailable_uses_current_reports_and_saved_starters(self):
        b=alert_body();b['options']=dict(reminder=False,incomplete=False,unavailable=True)
        for status in ('Out','IR','Inactive'):
            self.assertEqual(len(candidates(b,document(),schedule(),injuries(status),NOW)),1)
        for status in ('Questionable','Doubtful','Healthy'):
            self.assertEqual(candidates(b,document(),schedule(),injuries(status),NOW),[])
        self.assertEqual(candidates(b,document(),schedule(),injuries(at=NOW-49*3600),NOW),[])
        d=document();d['liveScoring']['matchup']['franchise'][0]['players']['player']['status']='nonstarter'
        self.assertEqual(candidates(b,d,schedule(),injuries(),NOW),[])
    def test_optout_tombstone_revision_and_cross_owner(self):
        a=self.service.alerts;b=alert_body();a.register('one','owner',b)
        b['revision']=2;b['options']['reminder']=True;a.register('one','owner',b)
        b['revision']=1;b['options']['reminder']=False;a.register('one','owner',b)
        raw=self.service.db.execute('SELECT body FROM lineup_alerts').fetchone()[0]
        self.assertTrue(json.loads(raw)['options']['reminder'])
        with self.assertRaises(PermissionError):a.delete('one','someone-else')
        a.delete('one','owner')
        with self.assertRaises(ValueError):a.register('one','owner',b)
    def test_alert_worker_deduplicates_and_revocation_during_read_cannot_send(self):
        s=self.service;s.alerts.register('one','owner',alert_body())
        self.mfl.export=lambda *args:schedule() if args[-1]=='nflSchedule' else injuries()
        calls=[]
        self.apns.send=lambda body,data,now,**kwargs:calls.append(json.loads(data)) or 200
        s.alerts.tick();self.now+=60;s.alerts.tick()
        self.assertEqual(len(calls),1)
        self.assertIn('lineup?',calls[0]['destination'])
        s.alerts.delete('one','owner');s.alerts.register('two','owner2',alert_body())
        self.now+=60
        def read(*args):
            s.alerts.delete('two','owner2');return document()
        self.mfl.read=read;s.alerts.tick();self.assertEqual(len(calls),1)
    def test_alerts_do_not_poll_scores_outside_kickoff_window(self):
        s=self.service;s.alerts.register('one','owner',alert_body())
        self.mfl.export=lambda *args:schedule(NOW+7200)
        for _ in range(10):s.alerts.tick();self.now+=60
        self.assertEqual(self.mfl.calls,0)
    def test_timeline_persists_negative_changes_gaps_and_does_not_duplicate(self):
        b=validate_subscription(subscription(),NOW,CONFIG['leagues']);t=self.service.timeline
        teams=read_matchup(document(),b);t.record(b,teams,updated_state(b,teams,NOW),NOW)
        newer=read_matchup(document(home='1'),b)
        t.record(b,newer,updated_state(b,newer,NOW+300),NOW+300)
        t.record(b,newer,{},NOW+300)
        result=t.read(2026,'12345',1,'0001','0002',NOW+300)
        self.assertEqual(len(result['events']),4)
        self.assertEqual({e['kind'] for e in result['events']},{'tracking','gap','player','team'})
        event=next(e for e in result['events'] if e['kind']=='player')
        self.assertEqual((event['previous'],event['current']),(3,1))
        self.service.db.commit();self.service.db.close()
        self.service=Service(CONFIG,self.temp.name+'/state.db',self.mfl,self.apns,clock=lambda:NOW+300)
        self.assertEqual(len(self.service.timeline.read(2026,'12345',1,'0002','0001',NOW+300)['events']),4)
        self.assertEqual(self.service.timeline.read(2026,'12345',2,'0002','0001',NOW+300)['events'],[])
        self.assertEqual(self.service.timeline.read(2026,'12345',1,'0002','0001',NOW+22*86400)['events'],[])
    def test_stat_context_requires_exact_identity_and_fresh_receipt(self):
        b=subscription();b['playerProfiles']={'10':dict(name='Test Receiver',team='JAC',position='TE')}
        state={'latestChange':{'playerID':'10'}}
        game=dict(home='JAC',away='CLE',status='Q3',statsStale=False,statsCheckedAt=NOW,players=[dict(name='Test Receiver',team='JAC',position='TE',groups=[dict(name='Receiving',stats=[dict(name='receiving touch downs',value='1')])])])
        enrich(state,b,dict(games=[game]),NOW);self.assertEqual(state['statContext'],'1 rec TD')
        enrich(state,b,dict(games=[game]),NOW+160);self.assertNotIn('statContext',state)
        game['statsCheckedAt']=NOW;game['players'][0]['name']='Different Person'
        enrich(state,b,dict(games=[game]),NOW);self.assertNotIn('statContext',state)

    def test_defense_context_matches_explicit_team_totals_only(self):
        b=subscription();b['playerProfiles']={'10':dict(name='Team Defense',team='JAC',position='DF')}
        state={'latestChange':{'playerID':'10'}}
        game=dict(home='JAC',away='CLE',status='Q3',defenseStale=False,defenseCheckedAt=NOW,defenses=[dict(name='Jaguars',team='JAC',position='DEF',groups=[dict(name='Team defense',stats=[dict(name='SK',value='5')])])])
        enrich(state,b,dict(games=[game]),NOW);self.assertEqual(state['statContext'],'5 sacks')
        enrich(state,b,dict(games=[game]),NOW+301);self.assertNotIn('statContext',state)

    def test_cam_stat_context_uses_shared_translation_with_id_name_and_team_guards(self):
        b=subscription();b['playerProfiles']={'17045':dict(name='Cam Skattebo',team='NYG',position='RB')}
        state={'latestChange':{'playerID':'17045'}}
        player=dict(providerID=31107,name='Cameron Skattebo',team='NYG',position='RB',mflID='17045',mflName='Cam Skattebo',
            groups=[dict(name='Rushing',stats=[dict(name='yards',value='81'),dict(name='rushing touch downs',value='1')])])
        game=dict(home='NYG',away='DAL',status='FT',statsStale=False,statsCheckedAt=NOW,players=[player])
        enrich(state,b,dict(games=[game]),NOW);self.assertEqual(state['statContext'],'81 rush yd · 1 rush TD')
        for field,value in [('mflID','99999'),('mflName','Cam Ward'),('team','TEN'),('position','QB')]:
            game['players']=[dict(player,**{field:value})]
            enrich(state,b,dict(games=[game]),NOW);self.assertNotIn('statContext',state)
        game['players']=[player,player]
        enrich(state,b,dict(games=[game]),NOW);self.assertNotIn('statContext',state)
