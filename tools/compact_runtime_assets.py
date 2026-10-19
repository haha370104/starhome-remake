"""Keep runtime dependencies only; place removed and original files outside Git."""
import argparse
import json
from pathlib import Path

from asset_pipeline.compact import compact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    result = compact(Path(__file__).resolve().parents[1], args.archive, args.apply)
    print(json.dumps({key: len(value) if isinstance(value, (dict, list)) else value
                      for key, value in result.items()}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
