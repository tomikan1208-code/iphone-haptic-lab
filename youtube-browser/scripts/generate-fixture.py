import subprocess
from pathlib import Path
import imageio_ffmpeg

root = Path(__file__).resolve().parents[1]
destination = root / ".build/BrowserFixture.mp4"
destination.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([
    imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-f", "lavfi", "-i", "color=c=0x18232b:s=320x180:r=10",
    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "180",
    "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "32k", "-movflags", "+faststart", str(destination)
], check=True, capture_output=True)
print(f"Generated real H.264/AAC browser test video: {destination.stat().st_size} bytes")
