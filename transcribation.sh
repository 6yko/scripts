#!/usr/bin/env bash
# shellcheck disable=2086

# MIT License

# Copyright (c) 2022 Daniils Petrovs
# Copyright (c) 2023 Jennifer Capasso
# Copyright (c) 2023 Thanh Tran

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Small shell script to more easily automatically download and transcribe live stream VODs.
# This uses YT-DLP, ffmpeg and the whisper-ctranslate2 
# The script will produce a zip file containing transcriptions for all the videos. 
# For each video, it downloads the audio and splits it into chunks (default 1 hour) to minimize memory usage during transcription. 
# The transcription is performed using Whisper with the default model "base.en."
# 
# Sample usage:
#
#   python3 -m pip install -U yt-dlp whisper-ctranslate2 [optional for gpu: nvidia-cublas-cu11 nvidia-cudnn-cu11]
#   chmod +x yt-wsp.sh
#   ./yt-wsp.sh https://www.youtube.com/watch?v=1234567890 https://www.youtube.com/watch?v=0987654321
#

set -Eeuo pipefail

# get script file location
SCRIPT_PATH="$(realpath ${BASH_SOURCE[0]})";
SCRIPT_DIR="${SCRIPT_PATH%/*}"

# Set the length of each chunk to divide the original audio into, default 3600s (1h)
AUDIO_CHUNK_LENGTH="${AUDIO_CHUNK_LENGTH:-3600}";

# Set the desired language for transcription, default is English (en)
WHISPER_LANG="${WHISPER_LANG:-ru}";
#WHISPER_LANG="${WHISPER_LANG:-en}";

# Set the desired model for transcription, default is "base.en"
WHISPER_MODEL="${WHISPER_MODEL:-base.en}";

# Set the desired device for transcription, default is "auto"
WHISPER_DEVICE="${WHISPER_DEVICE:-auto}";

msg() {
    echo >&2 -e "${1-}"
}

cleanup() {
    local -r clean_me="${1}"

    if [ -d "${clean_me}" ]; then
      msg "Cleaning up... ${clean_me}"
      rm -rf "${clean_me}"
    else
      msg "'${clean_me}' does not appear to be a directory!"
      exit 1
    fi
}

print_help() {
    echo "################################################################################"
    echo "Usage: ./yt-wsp.sh <video_url> [<video_url> ...]"
    echo "# See configurable env variables in the script; there are many!"
    echo "# This script will produce an MP4 muxed file in the working directory; it will"
    echo "# be named for the title and id of the video."
    echo "# passing in https://youtu.be/VYJtb2YXae8 produces a file named"
    echo "# 'Why_we_all_need_subtitles_now-VYJtb2YXae8-res.mp4'"
    echo "# Requirements: ffmpeg yt-dlp whisper-ctranslate2"
    echo "################################################################################"
}

check_requirements() {
    if ! command -v ffmpeg &>/dev/null; then
        echo "ffmpeg is required: https://ffmpeg.org";
        exit 1
    fi;

    if ! command -v whisper &>/dev/null; then
        echo "whisper is required!";
        exit 1
    fi;

#    if ! command -v yt-dlp &>/dev/null; then
#        echo "yt-dlp is required: https://github.com/yt-dlp/yt-dlp";
#        exit 1;
#    fi;

#    if ! command -v whisper-ctranslate2 &>/dev/null; then
#        echo "whisper-ctranslate2 is required: https://github.com/Softcatala/whisper-ctranslate2";
#        exit 1;
#    fi;

}

if [[ "${#}" -lt 1 ]]; then
    print_help;
    exit 1;
fi

if [[ "${1##-*}" == "help" ]]; then
    print_help;
    exit 0;
fi

check_requirements;

################################################################################
# create a temporary directory to work in
# set the temp_dir and temp_filename variables
################################################################################
FINAL_DIR="$(mktemp -d "${SCRIPT_DIR}/tmp.XXXXXX")"

process_video() {
    local source_url="${1}"
    msg "Processing video: ${source_url}"
    local temp_dir="$(mktemp -d "${SCRIPT_DIR}/tmp.XXXXXX")"
    local temp_filename="${temp_dir}/yt-dlp-filename"

    msg "Downloading ${source_url} VOD ..."
    yt-dlp \
        -f "m4a" \
        -o "${temp_dir}/%(title)s-%(id)s.vod.m4a" \
        --print-to-file "%(filename)s" "${temp_filename}" \
        --no-simulate \
        --no-write-auto-subs \
        --restrict-filenames \
        --embed-thumbnail \
        --embed-chapters \
        --xattrs \
        "${source_url}"

    local title_name="$(xargs basename -s .vod.m4a <"${temp_filename}")"

    msg "Whisper !!!!!!!!!!!!!!!!!!!!!!"
    whisper "${temp_dir}/${title_name}.vod.m4a"
    msg "Whisper FINISH!!!!!!"
#
#    msg "Extracting audio and resampling..."
#    ffmpeg -i "${temp_dir}/${title_name}.vod.m4a" \
#        -hide_banner \
#        -vn \
#        -loglevel error \
#        -ar 16000 \
#        -ac 1 \
#        -c:a pcm_s16le \
#        -y \
#        -f segment \
#        -segment_time "${AUDIO_CHUNK_LENGTH}" \
#        "${temp_dir}/${title_name}.vod-resampled.%03d.wav"

    local output_dir="${temp_dir}/transcriptions"
    mkdir -p "$output_dir"
#    local merged_txt="${output_dir}/merged.${title_name}.txt"
#
#    for wav_file in "${temp_dir}/${title_name}.vod-resampled."*.wav; do
#        msg "Transcribing to subtitle file for: ${wav_file}..."
#        local output_file="${output_dir}/$(basename "${wav_file}" .wav).txt"
#        whisper-ctranslate2 "$wav_file" --output_dir "${output_dir}" \
#            --model "${WHISPER_MODEL}" \
#            --language "${WHISPER_LANG}"\
#            --device "${WHISPER_DEVICE}" -f txt
#        cat "$output_file" >> "$merged_txt"
#    done
#
    mkdir -p "${FINAL_DIR}/${title_name}"
    mv "${output_dir}" "${FINAL_DIR}/${title_name}"

    # Clean up the temporary directory after processing each video
#    cleanup "$temp_dir"

    msg "Finished processing video: ${source_url}"
}

# Process each video URL provided as command-line arguments
for source_url in "${@}"; do
    process_video "${source_url}"
done

# Merge all zip files into a single zip file
merged_zip="${SCRIPT_DIR}/transcriptions.zip"
(cd "${FINAL_DIR}" && zip -r "${merged_zip}" .)

#cleanup "$FINAL_DIR"

#msg "All videos processed. The merged transcriptions can be found in ${merged_zip}"
