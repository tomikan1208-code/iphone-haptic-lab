"""Known musical timing and regressions from the Serenade model outputs."""
import unittest
import numpy as np
from haptic_arrangement import arrange, motif_beats, rhythm_grid
from music_rhythm import estimate_tempo, estimate_groove, match_beats, warp_sixteenths
from test_arrangement import fixture


class RhythmTests(unittest.TestCase):
    def test_quantized_137_bpm_is_not_rounded_to_136(self):
        period = 60/137
        beats = np.round(np.arange(128)*period, 2).tolist()
        self.assertAlmostEqual(estimate_tempo(beats), 137, delta=.03)
        beats.insert(35, beats[34]+.10)
        self.assertAlmostEqual(estimate_tempo(beats), 137, delta=.03)
        self.assertIsNone(estimate_tempo([0., .4, .8]))

    def test_tempo_is_not_fixed_to_reference_song(self):
        for bpm in (72, 95, 168, 220):
            beats = np.round(np.arange(96)*60/bpm, 2).tolist()
            self.assertAlmostEqual(estimate_tempo(beats), bpm, delta=.08)

    def test_extra_events_and_misses_reduce_one_to_one_agreement(self):
        reference = [0., .4, .8, 1.2]
        extra = [0., .02, .4, .42, .8, .82, 1.2, 1.22]
        match = match_beats(reference, extra)
        self.assertEqual(match['matches'], 4)
        self.assertEqual(match['precision'], .5)
        self.assertEqual(match['recall'], 1)
        self.assertAlmostEqual(match['f1'], 2/3)
        self.assertEqual(match_beats(reference, [0., .4])['recall'], .5)
        self.assertEqual(match_beats([], [])['f1'], 0)
        self.assertEqual(match_beats([.04,.08], [0.,.04])['matches'], 2)

    def test_serenade_duplicate_events_do_not_become_five_or_six_quarter_notes(self):
        graph = fixture()
        graph['duration'] = 166.
        graph['structure']['beats'] = [44.19,44.63,45.07,45.51,45.94,46.38,46.82,47.26,
                                      162.44,162.88,163.32,163.76,164.19,164.63,165.07,165.51]
        graph['structure']['downbeats'] = [44.19,45.94,47.69,162.44,164.19,165.95]
        graph['rhythm']['beats'] = [44.14,44.58,45.02,45.12,45.48,45.9,46.34,46.44,46.78,47.22,
                                   162.38,162.82,163.28,163.72,163.82,164.16,164.58,164.68,165.02,165.14,165.46]
        graph['rhythm']['downbeats'] = [44.14,45.9,47.66,162.38,164.16,165.9]
        bars, _, _, _, diagnostics = rhythm_grid(graph)
        self.assertEqual([b['meter'] for b in bars], [4,4,4,4])
        self.assertTrue(all(b['reliable'] for b in bars))
        self.assertEqual(len(diagnostics['removedBeats']), 5)

    def test_shared_ambiguous_duplicate_does_not_pass_reliability(self):
        graph = fixture()
        for source in ('structure', 'rhythm'):
            graph[source]['beats'].insert(2, .5)
        bars = rhythm_grid(graph)[0]
        self.assertFalse(bars[0]['reliable'])
        self.assertEqual(arrange(graph)[0]['arrangement']['bars'][0]['motif'], 'breath')

    def test_real_meter_and_tempo_changes_remain_observed(self):
        graph = fixture()
        bars = rhythm_grid(graph)[0]
        self.assertEqual([b['meter'] for b in bars], [3,3,3,4,4,4,4,4])
        self.assertTrue(all(b['reliable'] for b in bars))
        self.assertEqual([b['start'] for b in bars], graph['rhythm']['downbeats'][:-1])
        self.assertEqual(bars[-1]['beats'], graph['rhythm']['beats'][-4:])

    def test_corroborated_two_five_and_seven_beat_bars_are_not_forced_to_four(self):
        graph = fixture()
        meters = [4,4,5,5,2,2,7,7]
        beats, downbeats, start = [], [0.], 0.
        for meter in meters:
            beats.extend(start+np.arange(meter)*.4)
            start += meter*.4
            downbeats.append(start)
        graph['duration'] = start
        for source in ('structure','rhythm'):
            graph[source]['beats'] = beats
            graph[source]['downbeats'] = downbeats
        bars = rhythm_grid(graph)[0]
        self.assertEqual([b['meter'] for b in bars], meters)
        self.assertTrue(all(b['reliable'] for b in bars))

    def test_sixteenth_swing_requires_supported_onsets_and_moves_only_subdivision(self):
        period = .6
        beats = (np.arange(24)*period).tolist()
        times = np.arange(0, 14.4, .01)
        for split, expected in ((.5, 'straight'), (2/3, 'sixteenth-swing')):
            onset = np.zeros(len(times))
            for beat in beats:
                for phase in (0., .5*split, .5, .5+.5*split):
                    onset[int(round((beat+phase*period)/.01))] = 1.
            groove = estimate_groove(times, onset, beats, 0, 14.4)
            self.assertEqual(groove['kind'], expected)
            self.assertAlmostEqual(groove['split'], split, delta=.02)
            self.assertEqual(warp_sixteenths(2., groove['split']), 2.)
            self.assertEqual(warp_sixteenths(2.5, groove['split']), 2.5)
            self.assertAlmostEqual(warp_sixteenths(.75, groove['split']), .5+.5*split, delta=.01)
            self.assertEqual(motif_beats('offbeat', 3, groove)[0], 0)
            self.assertAlmostEqual(motif_beats('offbeat', 4, groove)[1], .5+.5*split, delta=.01)
        neutral = estimate_groove(times, np.zeros(len(times)), beats, 0, 14.4)
        self.assertEqual(neutral['split'], .5)
        self.assertEqual(neutral['kind'], 'unknown')

    def test_conflicting_onset_timing_does_not_force_shuffle(self):
        rng = np.random.default_rng(5)
        beats = (np.arange(48)*.6).tolist()
        times = np.arange(0, 28.8, .01)
        onset = np.zeros(len(times))
        for beat in beats:
            for half in (0., .5):
                phase = half+rng.uniform(.16, .4)
                onset[int(round((beat+phase*.6)/.01))] = 1.
        groove = estimate_groove(times, onset, beats, 0., 28.8)
        self.assertEqual(groove['kind'], 'unknown')
        self.assertEqual(groove['split'], .5)


if __name__ == '__main__':
    unittest.main()
