#!/usr/bin/env bash
# render.sh <input.puml> <output.png>
# Рендер C4-PlantUML диаграмм проекта в PNG.
#
# Требуется PlantUML + Graphviz и доступ в интернет (диаграммы подключают C4-PlantUML
# с raw.githubusercontent.com). Ограничение ширины снимается свойством PLANTUML_LIMIT_SIZE.
#
# Пример:
#   bash render.sh C2_ToBe_GoFuture.puml C2_ToBe_GoFuture.png
set -e
IN="$1"
OUT="$2"
java -DPLANTUML_LIMIT_SIZE=20000 -jar "${PLANTUML_JAR:-plantuml.jar}" -tpng -o "$(dirname "$OUT")" "$IN"
echo "OK -> $OUT"
