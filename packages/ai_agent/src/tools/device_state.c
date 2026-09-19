/*
 * Keep the openvela package build wired to the standalone implementation.
 * A C include wrapper works across Git clones and source archives where
 * symbolic links may not be preserved.
 */
#include "../../../../tools/device_state.c"
