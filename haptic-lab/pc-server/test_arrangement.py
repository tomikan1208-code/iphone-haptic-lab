"""Musical invariants and interchange tests; synthetic timing is known ground truth."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import numpy as np
from jsonschema import Draft202012Validator
from haptic_arrangement import arrange, export_ahap
from music_ai import cache_identity


def fixture():
    times = np.arange(0, 16, .02)
    # Observed bars: 3 beats, then 4 beats; intervals increase instead of fixed BPM.
    downbeats = [0., 1.2, 2.55, 4.15, 6.15, 8.35, 10.75, 13.35, 16.]
    beats = []
    for i, (start, end) in enumerate(zip(downbeats, downbeats[1:])):
        count = 3 if i < 3 else 4
        beats.extend(np.linspace(start, end, count, endpoint=False).tolist())
    active = (times < 6.15) | (times >= 8.35)
    features = dict(times=times.tolist())
    for name in ['mix', 'bass', 'drums', 'vocals', 'other']:
        features[name] = ((.1 if name != 'vocals' else .015)*active).tolist()
    for name in ['bass', 'drums', 'vocals']:
        features[name+'Onset'] = np.zeros(len(times)).tolist()
    segments = [dict(id='a', start=0., end=6.15, label='chorus', confidence=.9, mood='driving'),
                dict(id='quiet', start=6.15, end=8.35, label='break', confidence=.9, mood='gentle'),
                dict(id='b', start=8.35, end=16., label='chorus', confidence=.9, mood='driving')]
    return dict(duration=16., audioSHA256='a'*64, features=features,
                structure=dict(beats=beats, downbeats=downbeats, segments=segments),
                rhythm=dict(beats=beats, downbeats=downbeats))


class ArrangementTests(unittest.TestCase):
    def test_sub_frame_ending_section_keeps_metadata_and_serializes_for_phone(self):
        graph = fixture()
        graph['structure']['segments'][-1]['end'] = 15.99
        graph['structure']['segments'].append(dict(id='short-end', start=15.99, end=16.,
            label='outro', confidence=.9, mood='gentle'))
        original = copy.deepcopy(graph)
        for profile in ('standard', 'orchestral'):
            track, report = arrange(graph, profile=profile)
            section = track['arrangement']['sections'][-1]
            self.assertEqual((section['start'], section['end']), (15.99, 16.))
            self.assertIn(section['family'], ('pulse', 'sway', 'drive'))
            self.assertEqual(section['groove']['kind'], 'unknown')
            json.dumps(track, allow_nan=False)
            json.dumps(report, allow_nan=False)
        self.assertEqual(graph, original)

    def test_empty_feature_section_does_not_choose_the_family_of_later_choruses(self):
        graph = fixture()
        graph['structure']['segments'][0]['start'] = .019
        graph['structure']['segments'].insert(0, dict(id='short-start', start=.001, end=.019,
            label='chorus', confidence=.9, mood='driving'))
        track, _ = arrange(graph)
        choruses = [s for s in track['arrangement']['sections'] if s['label'] == 'chorus']
        self.assertEqual(choruses[1]['family'], 'drive')
        self.assertEqual(choruses[2]['family'], 'drive')

    def test_drifting_tempo_and_meter_follow_observed_bars_and_silence_stays_silent(self):
        graph = fixture()
        track, report = arrange(graph)
        bars = track['arrangement']['bars']
        self.assertEqual([b['meter'] for b in bars[:3]], [3, 3, 3])
        self.assertEqual([b['meter'] for b in bars[3:]], [4]*5)
        self.assertFalse(any(6.15 <= t['time'] < 8.35 for t in track['taps']))
        self.assertTrue(all(p['intensity'] == 0 for p in track['envelope'] if 6.15 <= p['time'] < 8.35))
        self.assertEqual(bars[4]['motif'], 'rest')
        choruses = [s for s in track['arrangement']['sections'] if s['label'] == 'chorus']
        self.assertEqual(choruses[0]['family'], choruses[1]['family'])
        self.assertGreater(len(track['taps']), 3)
        self.assertEqual(track, arrange(graph)[0])
        self.assertTrue(all(b['end']-b['start'] == end-start for b, (start, end) in
                            zip(bars, zip(graph['rhythm']['downbeats'], graph['rhythm']['downbeats'][1:]))))

    def test_disagreeing_rhythm_never_invents_four_four_and_uses_sustained_fallback(self):
        graph = fixture()
        graph['rhythm']['beats'] = [t+.2 for t in graph['rhythm']['beats']]
        track, _ = arrange(graph)
        self.assertLess(track['arrangement']['rhythmAgreement'], .75)
        self.assertEqual(track['arrangement']['rhythmSource'], 'all-in-one')
        self.assertTrue(any(not b['reliable'] for b in track['arrangement']['bars']))
        self.assertTrue(any(b['motif'] == 'breath' for b in track['arrangement']['bars']))
        self.assertFalse(track['taps'])

    def test_voice_overlap_and_hardware_levels_are_bounded_and_orchestral_is_sparser(self):
        graph = fixture()
        standard = arrange(graph)[0]
        orchestral = arrange(graph, profile='orchestral')[0]
        self.assertLess(len(orchestral['taps']), len(standard['taps']))
        for track in [standard, orchestral]:
            self.assertTrue(all(0 <= p['intensity'] <= .45 for p in track['envelope']))
            self.assertTrue(all(0 <= t['intensity'] <= .8 for t in track['taps']))
            self.assertTrue(all(b['time']-a['time'] >= .065-1e-6 for a,b in zip(track['taps'],track['taps'][1:])))
            for tap in track['taps']:
                nearest = min(track['envelope'], key=lambda p: abs(p['time']-tap['time']))
                self.assertLessEqual(nearest['intensity']+tap['intensity'], .95+1e-6)

    def test_beat_agreement_does_not_hide_a_conflicting_downbeat_phase(self):
        graph = fixture()
        graph['rhythm']['downbeats'] = [t+.2 for t in graph['rhythm']['downbeats']]
        track, _ = arrange(graph)
        self.assertEqual(track['arrangement']['rhythmAgreement'], 1)
        self.assertEqual(track['arrangement']['rhythmSource'], 'all-in-one')
        self.assertEqual(track['taps'], [])
        self.assertTrue(any(p['intensity'] > 0 for p in track['envelope']))

    def test_music_without_detectable_beats_keeps_free_phrases_and_no_invented_accents(self):
        graph = fixture()
        for source in ('structure', 'rhythm'):
            graph[source]['beats'] = []
            graph[source]['downbeats'] = []
        track, _ = arrange(graph)
        self.assertFalse(track['arrangement']['bars'])
        self.assertFalse(track['taps'])
        self.assertTrue(any(p['intensity'] > .01 for p in track['envelope']))
        self.assertTrue(all(p['intensity'] == 0 for p in track['envelope'] if 6.15 <= p['time'] < 8.35))

    def test_ahap_bundle_preserves_taps_and_continuous_curves_on_separate_players(self):
        track = arrange(fixture())[0]
        with tempfile.TemporaryDirectory() as directory:
            manifest = export_ahap(track, directory)
            restored = []
            for clip in manifest['clips']:
                self.assertLessEqual(clip['duration'], 8)
                for name, filename in clip['files'].items():
                    value = json.loads((Path(directory)/filename).read_text(encoding='utf-8'))
                    self.assertEqual(value['Version'], 1)
                    curves = [p['ParameterCurve'] for p in value['Pattern'] if 'ParameterCurve' in p]
                    if name == 'accents':
                        self.assertFalse(curves)
                        restored.extend(round(clip['start']+p['Event']['Time'],6) for p in value['Pattern'])
                    for curve in curves:
                        points = curve['ParameterCurveControlPoints']
                        self.assertLessEqual(len(points), 16)
                        self.assertEqual(points[0]['Time'], 0)
                        self.assertLessEqual(curve['Time']+points[-1]['Time'], clip['duration']+1e-6)
            self.assertEqual(restored, [t['time'] for t in track['taps']])

    def test_cache_changes_with_audio_profile_and_model_configuration(self):
        self.assertNotEqual(cache_identity('a'*64), cache_identity('b'*64))
        self.assertNotEqual(cache_identity('a'*64), cache_identity('a'*64, 'orchestral'))
        from unittest.mock import patch
        with patch('music_ai.PIPELINE_VERSION', 'new-composer'):
            changed = cache_identity('a'*64)
        self.assertNotEqual(changed, cache_identity('a'*64))

    def test_reused_work_directory_cannot_reuse_another_audio_stems(self):
        from contextlib import ExitStack
        from types import SimpleNamespace
        from unittest.mock import patch
        from music_ai import analyze_music
        with tempfile.TemporaryDirectory() as directory, ExitStack() as mocks:
            folder = Path(directory)
            for name, value in [('configure_models', 'cpu'), ('structure', {'segments': []}),
                                ('rhythm', {}), ('stem_features', {}), ('semantics', None)]:
                mocks.enter_context(patch('music_ai.'+name, return_value=value))
            separated = mocks.enter_context(patch('music_ai.separate', return_value=folder/'stems'))
            mocks.enter_context(patch.dict('sys.modules', {'torch': SimpleNamespace()}))
            arguments = (folder/'decoded.wav', folder, folder/'models', 16.)
            progress = lambda *_: None
            analyze_music(*arguments, 'a'*64, progress)
            analyze_music(*arguments, 'b'*64, progress)
            first, second = [call.args[1] for call in separated.call_args_list]
            self.assertNotEqual(first, second)
            self.assertEqual(second.name, cache_identity('b'*64))
            analyze_music(*arguments, 'b'*64, progress)
            self.assertEqual(separated.call_count, 2)


if __name__ == '__main__':
    unittest.main()
