"""Rhythm postprocessing using observed times, never a song-specific BPM or meter."""
import numpy as np


def ordered(values):
    return sorted(set(float(t) for t in values if np.isfinite(t)))


def match_beats(reference, candidate, tolerance=.07):
    """One-to-one temporal matching; extras reduce precision, misses reduce recall."""
    reference, candidate = ordered(reference), ordered(candidate)
    pairs = []
    i = j = 0
    while i < len(reference) and j < len(candidate):
        if abs(reference[i] - candidate[j]) <= tolerance:
            # Earliest compatible pairs maximize cardinality for sorted times.
            pairs.append((i, j))
            i += 1
            j += 1
        elif reference[i] < candidate[j]:
            i += 1
        else:
            j += 1
    precision = len(pairs)/len(candidate) if candidate else 0.
    recall = len(pairs)/len(reference) if reference else 0.
    f1 = 2*precision*recall/(precision+recall) if precision+recall else 0.
    return dict(matches=len(pairs), precision=precision, recall=recall, f1=f1)


def estimate_tempo(beats):
    """Fit multi-beat phrases before aggregating; reject jumps and duplicate events.

    A summary BPM does not replace the observed, possibly changing beat grid.
    """
    beats = np.asarray(ordered(beats))
    if len(beats) < 9:
        return None
    intervals = np.diff(beats)
    period = float(np.median(intervals))
    if period <= 0:
        return None
    breaks = np.flatnonzero((intervals < .65*period) | (intervals > 1.45*period)) + 1
    estimates = []
    for run in np.split(beats, breaks):
        if len(run) < 9:
            continue
        for start in range(0, len(run)-8, 8):
            phrase = run[start:start+32]
            index = np.arange(len(phrase))
            slope, intercept = np.polyfit(index, phrase, 1)
            residual = np.sqrt(np.mean((phrase-(intercept+slope*index))**2))
            if slope > 0 and residual < .08*slope:
                estimates.append(60/slope)
    return round(float(np.median(estimates)), 3) if estimates else None


def clean_duplicates(beats, reference):
    """Remove too-close quarter-note candidates only when another grid disambiguates.

    Real audio onsets remain in the features, including swung subdivisions.
    Ambiguous pairs remain present and fail the bar continuity check instead.
    """
    beats, reference = ordered(beats), np.asarray(ordered(reference))
    if len(beats) < 4 or not len(reference):
        return beats, []
    removed = []
    index = 0
    while index < len(beats)-1:
        local = np.diff(beats[max(0, index-8):index+10])
        period = float(np.median(local))
        if beats[index+1]-beats[index] < .5*period:
            distances = [float(np.min(np.abs(reference-t))) for t in beats[index:index+2]]
            distinct_reference = reference[(reference >= beats[index]-.07) & (reference <= beats[index+1]+.07)]
            dropped = None
            if len(distinct_reference) == 1 and min(distances) <= .07:
                if abs(distances[0]-distances[1]) >= .01-1e-9:
                    dropped = index if distances[0] > distances[1] else index+1
                else:
                    # Quantized models can put the reference exactly halfway
                    # between a normal beat and its duplicate. Check neighbors.
                    costs = []
                    for t in beats[index:index+2]:
                        gaps = []
                        if index > 0: gaps.append(t-beats[index-1])
                        if index+2 < len(beats): gaps.append(beats[index+2]-t)
                        costs.append(sum((gap/period-1)**2 for gap in gaps))
                    if abs(costs[0]-costs[1]) >= .04:
                        dropped = index if costs[0] > costs[1] else index+1
            if dropped is not None:
                removed.append(beats.pop(dropped))
                index = max(0, index-1)
                continue
        index += 1
    return beats, removed


def bar_continuity(beats, start, end):
    if len(beats) < 2 or abs(beats[0]-start) > .07:
        return False
    intervals = np.diff(beats + [end])
    period = float(np.median(intervals))
    return bool(period > 0 and np.all(np.abs(intervals/period-1) <= .25)
                and abs((end-start)/period-len(beats)) <= .3)


def estimate_groove(times, onset, beats, start, end):
    """Measure odd sixteenth-note timing; weak or conflicting evidence stays neutral."""
    times, onset = np.asarray(times), np.asarray(onset)
    unknown = dict(kind='unknown', split=.5, confidence=0., observations=0)
    if len(times) < 3 or len(beats) < 2 or float(onset.max()) <= 0:
        return unknown
    peaks = np.flatnonzero((onset[1:-1] >= onset[:-2]) & (onset[1:-1] > onset[2:]))+1
    peaks = peaks[(times[peaks] >= start) & (times[peaks] < end)]
    if not len(peaks):
        return unknown
    threshold = max(float(onset[peaks].max())*.15, float(np.percentile(onset[peaks], 50)))
    peaks = peaks[onset[peaks] >= threshold]
    phases, weights = [], []
    for left, right in zip(beats, beats[1:]):
        if left < start or right > end or right-left <= 0:
            continue
        for half in (0., .5):
            phase = (times[peaks]-left)/(right-left)
            selected = peaks[(phase >= half+.16) & (phase <= half+.4)]
            if len(selected):
                strongest = selected[np.argmax(onset[selected])]
                phases.append(((times[strongest]-left)/(right-left)-half)*2)
                weights.append(onset[strongest])
    unknown['observations'] = len(phases)
    if len(phases) < 12:
        return unknown
    phases, weights = np.asarray(phases), np.asarray(weights)
    centers = np.linspace(.45, .72, 28)
    support = [float(weights[np.abs(phases-center) <= .07].sum()/weights.sum()) for center in centers]
    best = int(np.argmax(support))
    if support[best] < .65:
        return unknown
    close = np.abs(phases-centers[best]) <= .07
    split = float(np.average(phases[close], weights=weights[close]))
    if split < .57:
        return dict(kind='straight', split=.5, confidence=support[best], observations=len(phases))
    if split < .60:
        return unknown
    return dict(kind='sixteenth-swing', split=round(split, 4), confidence=support[best], observations=len(phases))


def warp_sixteenths(position, split):
    beat = int(np.floor(position))
    phase = position-beat
    half = .5 if phase >= .5 else 0.
    within = (phase-half)*2
    warped = within*2*split if within <= .5 else split+(within-.5)*2*(1-split)
    return beat+half+.5*warped
