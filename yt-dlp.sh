#!/bin/bash

# Ensure yt-dlp is installed
if ! command -v yt-dlp &> /dev/null; then
    echo "Error: yt-dlp is not installed. Please install it first."
    exit 1
fi

# Define download directories
VIDEO_DIR="$HOME/Downloads/Videos"
AUDIO_DIR="$HOME/Downloads/Audio"

# Get URL from user argument or prompt
URL=$1
if [ -z "$URL" ]; then
    read -p "Enter Video/Playlist URL: " URL
fi

# Exit if URL is still empty
if [ -z "$URL" ]; then
    echo "No URL provided. Exiting."
    exit 1
fi

# Present interactive menu
echo "Select Download Mode:"
echo "1) Best Quality Video (MKV/MP4)"
echo "2) Extract Audio (MP3 320kbps)"
read -p "Enter choice [1-2]: " CHOICE

case $CHOICE in
    1)
        echo "Downloading video to $VIDEO_DIR..."
        mkdir -p "$VIDEO_DIR"
        yt-dlp -f "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b" \
               --merge-output-format mp4 \
               -o "$VIDEO_DIR/%(title)s.%(ext)s" \
               --embed-subs --embed-thumbnail --embed-metadata \
               "$URL"
        ;;
    2)
        echo "Downloading audio to $AUDIO_DIR..."
        mkdir -p "$AUDIO_DIR"
        # Requires ffmpeg installed for audio conversion
        yt-dlp -x --audio-format mp3 --audio-quality 0 \
               -o "$AUDIO_DIR/%(title)s.%(ext)s" \
               --embed-thumbnail --embed-metadata \
               "$URL"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Download completed successfully!"
