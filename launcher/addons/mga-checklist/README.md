# mga-checklist: an in-flight checklist tied to each control

A FlightGear add-on. **Ctrl-K** (or the **Checklist** menu) shows a small window with the
aircraft's checklist while you fly.

- Lines tied to a control or gauge go **green by themselves** when you set it, and turn amber
  again if you move it back. The control's live state is shown on the right in blue
  (magnetos BOTH, mixture 100%, flaps 25 deg, oil 72 psi ...).
- White lines have no control behind them (look outside, brief passengers ...): click one to tick it.
- The highlighted line is the next one to do. `<` and `>` (or the menu) change checklist;
  when every line is done the footer names the next checklist.
- The add-on's tied checklist also replaces the aircraft's in `/sim/checklists`, so
  Help > Aircraft Checklists shows the same green and amber.

`fgfs-mga` loads it with the other add-ons; `install.sh` puts it in
`~/.fgfs/FlightGear-2024.1-Addons-MGA/mga-checklist`.

## Aircraft

| Aircraft | File | Tied |
|---|---|---|
| PA28-161 Warrior II (160 hp) | `checklists/PA28-161-160.xml` | 113 of 202 lines check themselves, 146 show the control |
| Seneca II | `checklists/SenecaII.xml` | 44 of 85 lines check themselves, 54 show the control |
| Cessna 182S / 182T | the aircraft's own `c182s-checklists.xml` | already ties most lines; the window shows each tied line's control |

Any other aircraft uses its own checklist: lines the aircraft ties to a control go green by
themselves and show that control's value, the rest are ticked by hand. An aircraft with no
checklist says so.

To rebuild a tied file from the aircraft's own checklist (same words and order):

```
python3 tools/make-checklist.py pa28   ~/.fgfs/Aircraft/PA28/PA28-Checklists.xml    checklists/PA28-161-160.xml
python3 tools/make-checklist.py seneca ~/.fgfs/Aircraft/SenecaII/SenecaII-base.xml checklists/SenecaII.xml
```

Each profile at the top of that script maps checklist lines to properties; add a rule there
to tie another item. A line that already has a `<condition>` or `<now>` keeps it. A new
aircraft is a new profile and a new `checklists/<aircraft id>.xml` (the id is `/sim/aircraft`).

## From outside

Writing `/sim/mga-checklist/toggle` shows or hides the window and writing `1` or `-1` to
`/sim/mga-checklist/step` changes checklist (instructor panel, httpd).
