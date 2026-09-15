import unittest
import test_server as base
from test_server import game, NOW
import feed

def rows():
    return [dict(team=dict(id=tid,name="Test Team"),statistics=dict(sacks=dict(total=5),interceptions=dict(total=1),
        fumbles_recovered=dict(total=1),safeties=dict(total=0),int_touchdowns=dict(total=1),points_against=dict(total=points)))
        for tid,points in [(29,14),(4,20)]]

class DefenseTests(unittest.TestCase):
    def test_explicit_team_totals_and_points_allowed_revision(self):
        values=feed.defenses(rows(),game())
        stats={s['name']:s['value'] for s in values[0]['groups'][0]['stats']}
        self.assertEqual(stats,dict(SK='5',IC='1',FC='1',SF='0',TPA='14',**{'#IR':'1'}))
        self.assertNotIn('OPA',stats);self.assertNotIn('#DR',stats)
        wrong=rows();wrong[0]['statistics']['points_against']['total']=99
        stats={s['name']:s['value'] for s in feed.defenses(wrong,game())[0]['groups'][0]['stats']}
        self.assertNotIn('TPA',stats)
    def test_missing_duplicate_or_individual_rows_cannot_be_defense(self):
        for value in ([],rows()[:1],[rows()[0],rows()[0]]):
            with self.assertRaises(ValueError): feed.defenses(value,game())

class DefenseCadenceTests(unittest.TestCase):
    setUp=base.ServiceTests.setUp
    tearDown=base.ServiceTests.tearDown
    cached=base.ServiceTests.cached
    # Reuse setup helpers; inherited regression suite also exercises the new service.
    def test_defense_demand_is_opt_in_shared_and_bounded(self):
        self.cached('coverage',{'players':True})
        self.cached('games',[game()]);self.cached('box-1',dict(phase='Q3',players=[]))
        self.cached('roster-29',{});self.cached('roster-4',{})
        self.service.snapshot(1);self.service.tick();self.assertEqual(self.provider.calls,0)
        self.provider.value=rows()
        for _ in range(100):self.service.snapshot(1,defense_teams=['DAL'])
        self.service.tick();self.assertEqual(self.provider.calls,1)
        self.assertEqual(len(self.service.snapshot(1)['games'][0]['defenses']),2)
        self.now+=119
        self.cached('games',[game()]);self.cached('box-1',dict(phase='Q3',players=[]))
        self.service.tick();self.assertEqual(self.provider.calls,1)
        self.now+=1;self.service.tick();self.assertEqual(self.provider.calls,2)
    def test_defense_stays_inside_daily_ceiling(self):
        self.cached('games',[game()]);self.service.snapshot(1,defense_teams=['DAL'])
        self.service.db.execute('INSERT INTO usage VALUES (?,?)',(self.service.day(),6000));self.service.db.commit()
        self.service.tick();self.assertEqual(self.provider.calls,0)
