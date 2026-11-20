#!/bin/bash
# Повне видалення Optimizator з Mac
echo "Видалення Optimizator…"
osascript -e 'tell application id "com.optimizator.app" to quit' >/dev/null 2>&1
sleep 1

sudo /bin/bash -c '
  [ -x /usr/local/libexec/optimizator-smc ] && /usr/local/libexec/optimizator-smc auto-all
  rm -f /usr/local/libexec/optimizator-smc
  rm -rf "/Applications/Optimizator.app"
  pkgutil --forget com.optimizator.app >/dev/null 2>&1
'
rm -rf "$HOME/Library/Application Support/Optimizator"
echo "Готово. Optimizator видалено, вентилятори повернуто в автоматичний режим."
