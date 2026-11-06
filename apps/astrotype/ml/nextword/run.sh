#!/bin/bash
# Text, training, score and export for one language (README.md). Run on a Mac with an M chip:
#   ./run.sh en [minutes]
set -euo pipefail
lang=${1:?usage: run.sh en|es [minutes]}
minutes=${2:-150}
here=$(cd "$(dirname "$0")" && pwd)
kit="$here/../../ios/AstrotypeKit"
work="${NEXTWORD_WORK:-$HOME/astrotype-nextword}"
mkdir -p "$work/raw" "$work/data" "$work/runs"
cd "$here"

python3 -m venv "$work/venv"
source "$work/venv/bin/activate"
pip install -q torch pyarrow coremltools scikit-learn numpy

case $lang in
  en) parquet=https://huggingface.co/datasets/HuggingFaceFW/fineweb/resolve/main/sample/10BT/000_00000.parquet
      tatoeba=eng ;;
  es) parquet=https://huggingface.co/datasets/HuggingFaceFW/fineweb-2/resolve/main/data/spa_Latn/train/000_00000.parquet
      tatoeba=spa ;;
  *) echo "unknown language $lang"; exit 1 ;;
esac
[ -f "$work/raw/$lang.parquet.done" ] || { curl -L -C - --retry 5 -o "$work/raw/$lang.parquet" "$parquet" && touch "$work/raw/$lang.parquet.done"; }
if [ ! -f "$work/raw/${tatoeba}_sentences.tsv" ]; then
  curl -L -o "$work/raw/${tatoeba}_sentences.tsv.bz2" "https://downloads.tatoeba.org/exports/per_language/$tatoeba/${tatoeba}_sentences.tsv.bz2"
  bunzip2 -f "$work/raw/${tatoeba}_sentences.tsv.bz2"
fi
[ -f "$work/data/$lang/train.txt" ] || python3 make_text.py "$lang" "$work/raw/$lang.parquet" \
  --tatoeba "$work/raw/${tatoeba}_sentences.tsv" --max-sentences 3000000 --out "$work/data/$lang"

(cd "$kit" && swift run -c release astrotype-tools nexteval "$work/data/$lang/test.txt" --language "$lang") | tee "$work/runs/$lang-pairs.txt"
python3 train.py "$work/data/$lang" --out "$work/runs/$lang" --minutes "$minutes" | tee "$work/runs/$lang-train.log"
python3 evaluate.py "$work/runs/$lang/model.pt" "$work/data/$lang/test.txt" | tee "$work/runs/$lang-model.txt"
name="NextWord$(echo "${lang:0:1}" | tr a-z A-Z)${lang:1}"
python3 export.py "$work/runs/$lang/model.pt" "$here/../../ios/AstrotypeKeyboard/NextWord" --name "$name"
echo "Word pairs: $(cat "$work/runs/$lang-pairs.txt")"
echo "Model:      $(cat "$work/runs/$lang-model.txt")"
