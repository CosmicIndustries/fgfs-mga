#!/usr/bin/env python3
"""Apply the v2 probe-failure cleanup to the prepared Cyborg driver source."""
from pathlib import Path
import sys

path = Path("evo-cyborg-v2/hid-universal-pidff.c")
if not path.is_file():
    sys.exit(f"missing prepared driver source: {path}")

source = path.read_text()
init_anchor = """\terror = init_function(hdev, id->driver_data);
\tif (error) {
\t\thid_warn(hdev, "Error initialising force feedback\\n");
\t\tgoto err;
\t}
"""
if source.count(init_anchor) != 1:
    sys.exit("expected exactly one force-feedback initialization error path")
source = source.replace(init_anchor, init_anchor.replace("goto err;", "goto err_stop;"), 1)

return_anchor = """\treturn 0;
err:
\treturn error;
}
"""
if source.count(return_anchor) != 1:
    sys.exit("expected exactly one probe return/error-label block")
source = source.replace(
    return_anchor,
    """\treturn 0;
err_stop:
\thid_hw_stop(hdev);\t/* undo hid_hw_start, so no input devices are left behind */
err:
\treturn error;
}
""",
    1,
)
path.write_text(source)
print(f"patched {path}")
