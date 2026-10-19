"""Archive and split oversized runtime ZIPs for the temporary regular Git policy."""
import argparse
from pathlib import Path
from asset_pipeline.regular_git import prepare, apply


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    report = prepare(root, args.archive)
    if args.apply:
        apply(root, args.archive, report)
    print(f'Prepared {len(report["replacements"])} replacements; applied={report["applied"]}')


if __name__ == '__main__':
    main()
