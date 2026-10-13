import json
import pathlib
import sys

work, rtype = sys.argv[1], sys.argv[2]
bundle = json.load(sys.stdin)
written = 0
for entry in bundle.get("entry", []):
    resource = entry["resource"]
    meta = resource.get("meta", {})
    meta.pop("versionId", None)
    meta.pop("lastUpdated", None)
    target = pathlib.Path(work) / f"{rtype}-{resource['id']}.json"
    target.write_text(json.dumps(resource, indent=1))
    written += 1
print(written)
