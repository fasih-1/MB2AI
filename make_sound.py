import wave
import math
import struct
import os

# Create the folders if they don't exist
os.makedirs("ui/assets/sounds", exist_ok=True)
filename = "ui/assets/sounds/success.wav"

sample_rate = 44100
duration = 0.6  # Quick 0.6-second chime

with wave.open(filename, 'w') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    
    for i in range(int(sample_rate * duration)):
        t = float(i) / sample_rate
        
        # A sleek, modern two-tone chime (A5 to C#6)
        freq = 880.0 if t < 0.15 else 1108.73 
        
        # Smooth volume decay so it sounds like a glass bell
        env = math.exp(-7 * (t if t < 0.15 else t - 0.15))
        
        val = int(25000 * env * math.sin(2.0 * math.pi * freq * t))
        wav.writeframesraw(struct.pack('<h', val))

print(f"Premium chime synthesized directly to: {filename}")