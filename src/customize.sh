# Подключаем функцию проверки
. "$MODPATH/verify.inc.sh"

ui_print "****************************************"
ui_print "*   Verifying firmware compatibility   *"
ui_print "****************************************"

if ! verify_target_checksum; then
    ui_print "❌ Checksum mismatch or target file missing."
    ui_print "❌ Current firmware is incompatible."
    abort "❌ Installation aborted to prevent bootloop."
fi

ui_print "✅ Integrity check passed successfully."
