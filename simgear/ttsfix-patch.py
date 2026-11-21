"""Patch SimGear's AeonWave sound manager so a released source counts as stopped.

cleanup_removed_samples() calls sample_stop() (which releases a finished source) and then
is_sample_stopped() on the same sample. The OpenAL manager answers "stopped" for a released
source; the AeonWave one looked the id up, logged "unknown source id requested", got the null
emitter's state (not PROCESSED) and kept the sample forever, logging on every update.
Usage: python3 ttsfix-patch.py soundmgr_aeonwave.cxx
"""
import sys
p = sys.argv[1]
s = open(p).read()
if "released or never had a source" in s:
    print("already patched"); sys.exit(0)
old = '''bool SGSoundMgr::is_sample_stopped(SGSoundSample *sample)
{
#ifdef ENABLE_SOUND
    assert(sample->is_valid_source());
    aax::Emitter& emitter = d->get_emitter(sample->get_source());
    int result = emitter.state();
    return (result == AAX_PROCESSED);
#else
    return true;
#endif
}'''
new = '''bool SGSoundMgr::is_sample_stopped(SGSoundSample *sample)
{
#ifdef ENABLE_SOUND
    // A sample whose source was released (or never had a source) is stopped, as with OpenAL.
    // cleanup_removed_samples() asks right after sample_stop() released it.
    if (!sample->is_valid_source()) return true;
    auto source_it = d->_sources.find(sample->get_source());
    if (source_it == d->_sources.end()) return true;
    int result = source_it->second.state();
    return (result == AAX_PROCESSED);
#else
    return true;
#endif
}'''
assert s.count(old) == 1, "is_sample_stopped anchor"
s = s.replace(old, new)
# sample_play: if the buffer fails, the source is released, so the sample must not keep claiming it
old2 = '''        if (bufid == SGSoundMgr::FAILED_BUFFER ||
            bufid == SGSoundMgr::NO_BUFFER)
        {
            release_source(sample->get_source());
            return;
        }'''
new2 = '''        if (bufid == SGSoundMgr::FAILED_BUFFER ||
            bufid == SGSoundMgr::NO_BUFFER)
        {
            sample->no_valid_source();
            release_source(sample->get_source());
            return;
        }'''
assert s.count(old2) == 1, "sample_play anchor"
s = s.replace(old2, new2)
# stop(): AeonWave mixers take AAX_STOPPED; AAX_PROCESSED is an emitter state, so the mixer was never
# stopped ("aaxMixerSetState: Invalid parameter value" at exit) and could still be running at teardown
old3 = """    if (is_working()) {
        _active = false;
        TRY( d->_aax.set(AAX_PROCESSED) );"""
new3 = """    if (is_working()) {
        _active = false;
        enum aaxState mixer = d->_aax.state();
        if (mixer != AAX_STOPPED && mixer != AAX_PROCESSED)
            TRY( d->_aax.set(AAX_STOPPED) );"""
assert s.count(old3) == 1, "stop anchor"
s = s.replace(old3, new3)
open(p, "w").write(s)
print("patched")
