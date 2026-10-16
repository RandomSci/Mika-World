Placeholder transformation videos (synthetic: ffmpeg gradient + text + tone) used to test the cutscene player.
They are NOT shipped as .ogv on purpose (the game would play them for real). To reproduce the test:

    tools/transformations/convert.sh tools/transformations/placeholders/mika_10.mp4 mika 10
    tools/transformations/convert.sh tools/transformations/placeholders/luna_10.mp4 luna 10

(luna_10.mp4 is portrait 576x1024 on purpose: it checks the letterboxing.) Delete the resulting .ogv files before
merging, and drop the real AI-generated videos in instead.
