#!/system/bin/sh
MODDIR=${0%/*}

# Подключаем функцию проверки
. "$MODDIR/verify.inc.sh"

if ! verify_target_checksum; then
    # Прошивка обновилась: деактивируем модуль до монтирования overlay
    touch "$MODDIR/disable"
fi
