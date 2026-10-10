import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description="Offline server save upgrade: back up schema 3, add ground items, write schema 4.")
    parser.add_argument("save", type=Path, help="Server save path; stop the game/server before running.")
    args = parser.parse_args()
    path = args.save.resolve()
    original = path.read_bytes()
    document = json.loads(original)
    if set(document) != {"schema_version", "players"} or document["schema_version"] != 3:
        raise SystemExit("Expected an unmodified schema-3 server save; nothing written.")
    if not isinstance(document["players"], dict) or any(
        player.get("schema_version") != 3 for player in document["players"].values()
    ):
        raise SystemExit("Player records do not match schema 3; nothing written.")
    backup = path.with_name(path.name + ".before-ground-items-" + str(time.time_ns()))
    shutil.copy2(path, backup)
    if backup.read_bytes() != original:
        raise SystemExit("Backup verification failed; nothing written.")
    document.update(schema_version=4, ground_cleanup_at=(int(time.time()) // 86400 + 1) * 86400, ground_items={})
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as output:
        json.dump(document, output, ensure_ascii=False, separators=(",", ":"))
        output.flush()
        os.fsync(output.fileno())
        staged = Path(output.name)
    try:
        if path.read_bytes() != original or json.loads(staged.read_bytes())["players"] != json.loads(original)["players"]:
            raise SystemExit("Save changed or player verification failed; original retained.")
        os.chmod(staged, path.stat().st_mode & 0o777)
        os.replace(staged, path)
    finally:
        staged.unlink(missing_ok=True)
    print(f"Upgraded {path.name}; verified backup: {backup.name}; player records unchanged.")


if __name__ == "__main__":
    main()
