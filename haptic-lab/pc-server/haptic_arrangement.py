"""Arrange a tactile instrument from a music graph, then render independent layers.

This composer is deterministic constrained search, not a learned generator. Neural
models supply structure, rhythm, separated instruments and audio/text similarity.
"""
import bisect
import copy
import math
from pathlib import Path

import numpy as np
from music_ai import PIPELINE_VERSION, write_json
from music_rhythm import match_beats, clean_duplicates, bar_continuity, estimate_groove, warp_sixteenths

MOTIFS = {
    'sparse': ([0.0], .18),
    'pulse': ([0.0, .5], .24),
    'drive': ([0.0, .25, .5, .75], .29),
    'offbeat': ([0.0, .375, .625, .875], .25),
    'breath': ([], .34),
    'rest': ([], 0.0),
}
FAMILIES = {'drive': ['drive', 'offbeat', 'sparse', 'rest'],
            'pulse': ['pulse', 'sparse', 'rest'], 'sway': ['breath', 'pulse', 'rest']}


def normalized(values):
    values = np.asarray(values, dtype=float)
    reference = max(float(np.percentile(values, 95)), 1e-8)
    return np.clip(values / reference, 0, 1)


def rhythm_grid(graph):
    original, independent = graph['structure'], graph['rhythm']
    beat_match = match_beats(original['beats'], independent['beats'])
    downbeat_match = match_beats(original['downbeats'], independent['downbeats'])
    agreement, downbeat_agreement = beat_match['f1'], downbeat_match['f1']
    # A second network must agree before it can replace the structure model's meter.
    chosen = independent if agreement >= .75 and downbeat_agreement >= .7 else original
    other = original if chosen is independent else independent
    cleaned, removed = clean_duplicates(chosen['beats'], other['beats'])
    other_beats, _ = clean_duplicates(other['beats'], chosen['beats'])
    beats = [t for t in cleaned if 0 <= t < graph['duration']]
    downbeats = sorted(set(t for t in chosen['downbeats'] if 0 <= t <= graph['duration']))
    bars = []
    for start, end in zip(downbeats, downbeats[1:]):
        inside = [t for t in beats if start - .04 <= t < end - .04]
        if not 2 <= len(inside) <= 7 or not .5 <= end-start <= 8: continue
        local_reference = [t for t in other_beats if start-.07 <= t < end-.07]
        local_match = match_beats(local_reference, inside)
        nearby_downbeats = [t for t in other['downbeats'] if start-.07 <= t <= end+.07]
        downbeat_matches = match_beats([start, end], nearby_downbeats)
        reliable = (local_match['f1'] >= .85 and downbeat_matches['matches'] == 2
                    and bar_continuity(inside, start, end))
        bars.append(dict(start=start, end=end, beats=inside, meter=len(inside), reliable=reliable))
    diagnostics = dict(beatMatch=beat_match, downbeatMatch=downbeat_match,
                       removedBeats=removed, agreementMethod='one-to-one F1 within 70 ms')
    return bars, agreement, downbeat_agreement, 'beat-this' if chosen is independent else 'all-in-one', diagnostics


def motif_beats(motif, meter, groove):
    positions = ([0.] + [beat+.75 for beat in range(meter-1)] if motif == 'offbeat'
                 else [position*meter for position in MOTIFS[motif][0]])
    return [warp_sixteenths(position, groove['split']) for position in positions]


def arrange(graph, spectrum=None, profile='standard'):
    duration = graph['duration']
    raw = graph['features']
    times = np.asarray(raw['times'])
    features = {name: normalized(raw[name]) for name in ('mix', 'bass', 'drums', 'vocals', 'other')}
    absolute = np.asarray(raw['mix'])
    audible = absolute > max(.0001, float(absolute.max()) * .008)
    bars, agreement, downbeat_agreement, rhythm_source, diagnostics = rhythm_grid(graph)
    observed_beats = sorted(set(t for bar in bars for t in bar['beats']))
    sections = copy.deepcopy(graph['structure']['segments'])
    # Repeat families are chosen per functional label + mood; chorus returns reuse its family.
    recurring = {}
    for section in sections:
        mask = (times >= section['start']) & (times < section['end'])
        if not mask.any(): continue
        energy = float(features['mix'][mask].mean())
        drums = float(features['drums'][mask].mean())
        vocal = float(np.mean(features['vocals'][mask] > .3))
        mood = section.get('mood', 'gentle')
        # Reserve the denser vocabulary for percussive choruses or very active verses.
        percussive_chorus = section['label'] == 'chorus' and drums > .28
        family = 'drive' if (percussive_chorus or drums > .65) and mood in ('driving', 'bright', 'tense') else 'pulse'
        if mood in ('gentle', 'floating', 'solemn') or profile == 'orchestral': family = 'sway'
        if section['confidence'] < .5: family = 'pulse'
        key = 'chorus' if section['label'] == 'chorus' else section['label'] + ':' + mood
        family = recurring.setdefault(key, family)
        section.update(family=family, energy=energy, vocalOccupancy=vocal)
        section['groove'] = estimate_groove(times, raw['drumsOnset'], observed_beats,
                                           section['start'], section['end'])
    section_starts = [s['start'] for s in sections]
    for bar in bars:
        index = max(0, bisect.bisect_right(section_starts, bar['start'])-1)
        section = sections[index]
        mask = (times >= bar['start']) & (times < bar['end'])
        energy = float(features['mix'][mask].mean()) if mask.any() else 0
        vocal = float(np.mean(features['vocals'][mask] > .3)) if mask.any() else 0
        target = (4.2 if section['label'] == 'chorus' else 2.4) * (.55+.45*energy) * (1-.18*vocal)
        if profile == 'orchestral': target *= .25
        bar.update(sectionID=section['id'], family=section.get('family', 'pulse'),
                   energy=energy, vocalOccupancy=vocal, target=target,
                   silent=not mask.any() or not audible[mask].any())
    # Beam search trades off phrasing, stable motif returns and accumulating activity.
    drum_attacks = normalized(raw['drumsOnset'])
    beam = [(0.0, [], None, 0.0)]
    for index, bar in enumerate(bars):
        candidates = ['rest'] if bar['silent'] else FAMILIES[bar['family']]
        if not bar['reliable'] and not bar['silent']: candidates = ['breath']
        expanded = []
        for cost, path, previous, fatigue in beam:
            for motif in candidates:
                _, bed = MOTIFS[motif]
                section = next(s for s in sections if s['id'] == bar['sectionID'])
                hits = motif_beats(motif, len(bar['beats']), section['groove'])
                activity = len(hits) * .12 + bed * 2
                accumulated = fatigue * .72 + activity
                fit = (len(hits)-bar['target'])**2 * .3
                if hits:
                    beat_axis = bar['beats'] + [bar['end']]
                    candidate_times = np.interp(np.asarray(hits),
                                                np.arange(len(beat_axis)), beat_axis)
                    match = np.interp(candidate_times, times, drum_attacks)
                    fit += .45*(1-float(match.mean()))
                change = .2 if previous and previous != motif else 0
                excess = max(0, accumulated-3.2)**2 * .8
                repetition = .3 if len(path) >= 5 and len(set(path[-5:]+[motif])) == 1 else 0
                expanded.append((cost+fit+change+excess+repetition, path+[motif], motif, accumulated))
        beam = sorted(expanded, key=lambda item: (item[0], item[1]))[:8]
    choices = beam[0][1] if beam else []
    bed = np.zeros(len(times)); sharpness = np.full(len(times), .25)
    covered = np.zeros(len(times), dtype=bool)
    taps = []
    for bar, motif in zip(bars, choices):
        bar['motif'] = motif
        _, bed_gain = MOTIFS[motif]
        section = next(s for s in sections if s['id'] == bar['sectionID'])
        positions = motif_beats(motif, len(bar['beats']), section['groove'])
        mask = (times >= bar['start']) & (times < bar['end'])
        covered[mask] = True
        phase = (times[mask]-bar['start']) / (bar['end']-bar['start'])
        # The sustained voice follows bass/other instruments, with a phrase-shaped envelope.
        contour = .7 + .3*np.sin(np.pi*phase)**2
        if motif == 'breath': contour = np.sin(np.pi*phase)**2
        if section['label'] == 'chorus': bed_gain *= 1.12
        bed[mask] = bed_gain * (.55*features['bass'][mask]+.45*features['other'][mask]) * contour
        bed[mask] *= 1-.35*features['vocals'][mask]
        sharpness[mask] = np.clip(.18+.5*features['drums'][mask], .12, .7)
        # Convert fractional beat positions through the observed grid; no fixed 4/4 or BPM.
        beat_axis = bar['beats'] + [bar['end']]
        for position in positions:
            instant = float(np.interp(position, np.arange(len(beat_axis)), beat_axis))
            onset = np.asarray(raw['drumsOnset'])
            near = np.flatnonzero(np.abs(times-instant) <= .045)
            if len(near):
                peak = int(near[np.argmax(onset[near])])
                if onset[peak] > .05: instant = float(times[peak])
            sample = min(len(times)-1, max(0, int(np.searchsorted(times, instant))))
            if not audible[sample] or instant >= duration or not bar['start'] <= instant < bar['end']: continue
            intensity = (.24+.43*features['drums'][sample]+.13*features['bass'][sample])
            intensity *= (1-.28*features['vocals'][sample]) * (1 if position == 0 else .68)
            if profile == 'orchestral': intensity *= .5
            taps.append(dict(time=round(instant, 6), intensity=round(min(.8, intensity), 6),
                             sharpness=round(.35+.5*features['drums'][sample], 6),
                             role='accent' if position == 0 else 'groove', priority=1.0 if position == 0 else .55))
    # Unmetered music and partial opening/ending bars retain a free sustained phrase.
    for section in sections:
        mask = (times >= section['start']) & (times < section['end']) & ~covered
        phase = (times[mask]-section['start']) / max(.02, section['end']-section['start'])
        bed[mask] = (.16+.08*np.sin(np.pi*phase)**2) * (
            .5*features['bass'][mask]+.5*features['other'][mask]) * (1-.35*features['vocals'][mask])
    # Quiet regions, including leading/trailing silence, are hard rests after smoothing.
    kernel = np.exp(-.5*(np.arange(-5, 6)/1.5)**2)
    kernel /= kernel.sum()
    bed = np.convolve(np.pad(bed, (5, 5), mode='edge'), kernel, mode='valid')
    bed[~audible] = 0
    bed = np.clip(bed, 0, .45)
    safe_taps = []
    for tap in sorted(taps, key=lambda t: (t['time'], -t['priority'])):
        if safe_taps and tap['time']-safe_taps[-1]['time'] < .065: continue
        safe_taps.append(tap)
        nearby = np.abs(times-tap['time']) < .05
        bed[nearby] = np.minimum(bed[nearby], .95-tap['intensity'])
    envelope = [dict(time=round(float(t), 6), bass=round(float(features['bass'][i]), 6),
                     energy=round(float(features['mix'][i]), 6), mid=round(float(features['other'][i]), 6),
                     high=round(float(features['drums'][i]), 6), sharpness=round(float(sharpness[i]), 6),
                     intensity=round(float(bed[i]), 6)) for i, t in enumerate(times)]
    envelope.append(dict(envelope[-1], time=duration, intensity=0, bass=0, energy=0))
    # Compact score travels to iPhone; full graph/activations remain on PC.
    summary_sections = [{key: s[key] for key in ('id', 'start', 'end', 'label', 'confidence', 'mood', 'family', 'groove')}
                        for s in sections]
    summary_bars = [{key: b[key] for key in ('start', 'end', 'meter', 'sectionID', 'motif', 'reliable')}
                    for b in bars]
    score = dict(version=1, sections=summary_sections, bars=summary_bars,
                 rhythmAgreement=agreement, downbeatAgreement=downbeat_agreement, rhythmSource=rhythm_source,
                 rhythmDiagnostics=diagnostics,
                 limits=dict(maximumBed=.45, maximumTap=.8, minimumTapSpacing=.065),
                 method='Neural analysis + deterministic motif beam search')
    track = dict(version=3, audioSHA256=graph['audioSHA256'], duration=duration,
                 envelope=envelope, taps=safe_taps, arrangement=score)
    if spectrum is not None: track['spectrum'] = spectrum
    return track, dict(score=score, decisions=sections, beamCost=beam[0][0] if beam else 0)


def export_ahap(track, destination, chunk_seconds=8):
    """Separate players keep bed curves from scaling accent events. Each clip <=30 s."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    manifest = dict(version=1, duration=track['duration'], pipeline=PIPELINE_VERSION,
                    playback='Start bed and accents on separate players at the same engine time.', clips=[])
    for index, start in enumerate(np.arange(0, track['duration'], chunk_seconds)):
        end = min(track['duration'], float(start)+chunk_seconds)
        frames = track['envelope']
        axis = [p['time'] for p in frames]
        sample_times = [float(start)] + [p['time'] for p in frames if start < p['time'] < end] + [end]
        intensity = np.interp(sample_times, axis, [p['intensity'] for p in frames])
        sharp = np.interp(sample_times, axis, [p['sharpness'] for p in frames])
        bed_pattern = [{'Event': dict(Time=0, EventType='HapticContinuous', EventDuration=end-start,
            EventParameters=[dict(ParameterID='HapticIntensity', ParameterValue=1),
                             dict(ParameterID='HapticSharpness', ParameterValue=0)])}]
        for parameter, values in [('HapticIntensityControl', intensity), ('HapticSharpnessControl', sharp)]:
            for offset in range(0, len(sample_times)-1, 15):
                points = sample_times[offset:offset+16]
                bed_pattern.append({'ParameterCurve': dict(ParameterID=parameter, Time=points[0]-start,
                    ParameterCurveControlPoints=[dict(Time=t-points[0], ParameterValue=float(v))
                                                 for t, v in zip(points, values[offset:offset+16])])})
        taps = [{'Event': dict(Time=t['time']-start, EventType='HapticTransient',
                    EventParameters=[dict(ParameterID='HapticIntensity', ParameterValue=t['intensity']),
                                     dict(ParameterID='HapticSharpness', ParameterValue=t['sharpness'])])}
                for t in track['taps'] if start <= t['time'] < end]
        files = {}
        for name, pattern in [('bed', bed_pattern), ('accents', taps)]:
            if not pattern: continue
            filename = f'{index:03d}-{name}.ahap'
            write_json(destination / filename, dict(Version=1, Metadata=dict(Project='Reson', Layer=name), Pattern=pattern))
            files[name] = filename
        manifest['clips'].append(dict(start=float(start), duration=end-start, files=files))
    write_json(destination / 'manifest.json', manifest)
    return manifest
