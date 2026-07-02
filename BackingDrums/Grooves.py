import os
import random
from mido import MidiFile, MidiTrack, Message, MetaMessage

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "Output")

# Standard GM Drum Map Definitions
KICK = 36
SNARE = 38
CLOSED_HAT = 42
RIDE = 51

def humanize_velocity(base_vel, variance=8):
    return max(40, min(127, base_vel + random.randint(-variance, variance)))

def create_synchronized_loop(filename, time_sig_num, time_sig_den, pattern_func, target_ticks=11520):
    """Generates a loop forced to an exact absolute tick length so parallel tracks align perfectly."""
    mid = MidiFile(ticks_per_beat=480)
    track = MidiTrack()
    mid.tracks.append(track)

    track.append(MetaMessage('time_signature', numerator=time_sig_num, denominator=time_sig_den, time=0))
    track.append(MetaMessage('track_name', name=filename.replace('.mid', ''), time=0))

    events = []
    ticks_per_quarter = 480
    
    # Calculate how many ticks a single bar takes for this meter
    if time_sig_num == 6 and time_sig_den == 8:
        ticks_per_bar = 1440
    elif time_sig_num == 2 and time_sig_den == 4:
        ticks_per_bar = 960
    else:
        ticks_per_bar = time_sig_num * ticks_per_quarter

    # Calculate exactly how many bars fit into our master synchronization block
    total_bars = target_ticks // ticks_per_bar

    for bar in range(total_bars):
        bar_start_tick = bar * ticks_per_bar
        pattern_func(events, bar_start_tick, ticks_per_quarter)

    # Sort events
    events.sort(key=lambda x: (x['tick'], 0 if x['type'] == 'note_off' else 1))

    # Compile relative delta values
    last_tick = 0
    for ev in events:
        delta = ev['tick'] - last_tick
        track.append(Message(ev['type'], note=ev['note'], velocity=ev['velocity'], time=delta, channel=9))
        last_tick = ev['tick']

    # Strict master cutoff alignment
    final_delta = target_ticks - last_tick
    track.append(MetaMessage('end_of_track', time=final_delta))
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, filename)
    mid.save(out_path)
    print(f"Sync-Loop Matrix: {out_path} spans {total_bars} bars at {time_sig_num}/{time_sig_den} (Exactly {target_ticks} ticks)")

def add_hit(events, note, velocity, start_tick, duration):
    events.append({'type': 'note_on', 'note': note, 'velocity': velocity, 'tick': start_tick})
    events.append({'type': 'note_off', 'note': note, 'velocity': 0, 'tick': start_tick + duration})

# --- RE-ALIGNED PATTERN ENGINE ---

def pattern_straight_44(events, bar_start, tpq):
    step_ticks = 240
    note_length = 230
    for step in range(8):
        tick = bar_start + (step * step_ticks)
        hat_vel = humanize_velocity(95) if step % 2 == 0 else humanize_velocity(75)
        add_hit(events, CLOSED_HAT, hat_vel, tick, note_length)
        if step in [0, 4]:
            add_hit(events, KICK, humanize_velocity(105), tick, note_length)
        if step in [2, 6]:
            add_hit(events, SNARE, humanize_velocity(100), tick, note_length)

def pattern_shuffle_44(events, bar_start, tpq):
    step_ticks = 160
    note_length = 150
    for step in range(12):
        tick = bar_start + (step * step_ticks)
        pos_in_beat = step % 3
        if pos_in_beat in [0, 2]:
            hat_vel = humanize_velocity(95 if pos_in_beat == 0 else 80)
            add_hit(events, CLOSED_HAT, hat_vel, tick, note_length)
        if step in [0, 6]:
            add_hit(events, KICK, humanize_velocity(105), tick, note_length)
        if step in [3, 9]:
            add_hit(events, SNARE, humanize_velocity(100), tick, note_length)

def pattern_ballad_68(events, bar_start, tpq):
    step_ticks = 240
    note_length = 230
    for step in range(6):
        tick = bar_start + (step * step_ticks)
        hat_vel = humanize_velocity(90 if step == 0 else 75)
        add_hit(events, CLOSED_HAT, hat_vel, tick, note_length)
        if step == 0:
            add_hit(events, KICK, humanize_velocity(110), tick, note_length)
        if step == 3:
            add_hit(events, SNARE, humanize_velocity(105), tick, note_length)

def pattern_polka_24(events, bar_start, tpq):
    step_ticks = 240
    note_length = 230
    for step in range(4):
        tick = bar_start + (step * step_ticks)
        on_inst = RIDE if step % 2 == 0 else CLOSED_HAT
        add_hit(events, on_inst, humanize_velocity(85), tick, note_length)
        if step in [0, 2]:
            add_hit(events, KICK, humanize_velocity(105), tick, note_length)
        if step in [1, 3]:
            add_hit(events, SNARE, humanize_velocity(95), tick, note_length)

if __name__ == "__main__":
    print("Generating Master-Aligned Grid Loops...")
    # All files forced to identical absolute lengths
    create_synchronized_loop("Loop_Straight_44.mid", 4, 4, pattern_straight_44)
    create_synchronized_loop("Loop_Shuffle_44.mid",  4, 4, pattern_shuffle_44)
    create_synchronized_loop("Loop_Ballad_68.mid",   6, 8, pattern_ballad_68)
    create_synchronized_loop("Loop_Polka_24.mid",    2, 4, pattern_polka_24)
    print("\nPhase-locked matrix complete!")