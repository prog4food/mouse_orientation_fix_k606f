# Fix: Перепутанные оси у мыши в режиме Pointer Capture (Lenovo K606F / Android 13)

## 1. Описание проблемы и окружение
* **Устройство:** Планшет Lenovo (`K606F`), Android 13 (`YT-K606F_S510234_231224_ROW`), наличие Root (Magisk).
* **Физический дисплей:** Портретная матрица `1350x2160` (`DisplayWidth: 1350px, DisplayHeight: 2160px`), работающая в ландшафтном режиме через постоянную трансформацию окна `ROT_270` (`logicalSize = 2160x1350`).
* **Симптомы:**
  * На рабочем столе / в лаунчере (`SOURCE_MOUSE = 0x2002`, `Mode: POINTER`) курсор мыши двигается **правильно**.
  * В полноэкранных приложениях при захвате указателя (`SOURCE_MOUSE_RELATIVE = 0x20004`, `Mode: POINTER_CAPTURE`, например, в Moonlight, Winlator и 3D-играх) оси `AXIS_X (0)` и `AXIS_Y (1)` перепутаны местами:
    * Мышь вверх → влево
    * Мышь вниз → вправо
    * Мышь влево → вниз
    * Мышь вправо → вверх
* **Релевантные issues:**
  * https://github.com/moonlight-stream/moonlight-android/issues/1240
  * https://github.com/moonlight-stream/moonlight-android/issues/1028
  * https://github.com/ddnet/ddnet/issues/9410
  * https://github.com/AngelAuraMC/Amethyst-Android/issues/335
  * https://github.com/PojavLauncherTeam/PojavLauncher/issues/5463


## 2. Корневая причина бага (Root Cause Analysis)
В Android 13 логика обработки мыши вынесена из `libinputflinger.so` в библиотеку **`/system/lib64/libinputreader.so`** (класс `android::CursorInputMapper`).

1. **Инвертированная проверка `orientationAware` в `CursorInputMapper::configure` (`0x00468100`):**
```c
   uint32_t x8_27 = *(uint8_t*)((char*)this + 0x15); // mParameters.orientationAware
   *(uint32_t*)((char*)this + 0x100) = 0;            // mOrientation = 0
   if (!x8_27 || !*(uint8_t*)((char*)this + 0x14))   // Костыль Lenovo: инвертирован !x8_27
```

При стандартном `OrientationAware: false` код Lenovo принудительно выставляет мыши `mOrientation = 3` (`ROTATION_270`, смещение `this + 0x100`).

* *Примечание:* Попытка задать `cursor.orientationAware = 1` через `.idc` файл (`/data/system/devices/idc/Vendor_XXXX_Product_YYYY.idc`) приводит к сбросу `mOrientation` в `0`, что ломает оси мыши еще и в лаунчере.

2. **Пропуск компенсации поворота для `0x20004` в `CursorInputMapper::sync` (`0x00468648`):**
```c
00468610  int32_t x9_2 = *(uint32_t*)((char*)this + 0x3c); // mSource
...
00468634  float var_1308 = v1_1; // raw deltaY
00468634  float var_1304 = v0;   // raw deltaX
00468648  if (x9_2 != 0x20004)   // Пропуск ротации при SOURCE_MOUSE_RELATIVE!
00468648  {
0046864c      int32_t x9_3 = *(uint32_t*)((char*)this + 0x100); // mOrientation (3)
00468654      if (x9_3 == 3) {
00468680          var_1304 = -(v1_1); // deltaX = -rawY
00468688          var_1308 = v0;      // deltaY = rawX
00468654      }
              ...
00468648  }
```

* Для обычного курсора (`0x2002`) выполняется предварительный поворот дельт (`mOrientation == 3`), который затем компенсируется матрицей окна `ROT_270` в `InputDispatcher`.
* Для `SOURCE_MOUSE_RELATIVE` (`0x20004`) блок на `0x00468648` пропускает предварительный поворот, но `InputDispatcher` все равно применяет матрицу окна `ROT_270` к координатам `AXIS_X (0)` и `AXIS_Y (1)`, из-за чего приложение получает повернутые оси.


## 3. Способы решения
### Вариант А: Бинарный патч `/system/lib64/libinputreader.so` (Основной системный фикс)

* **Цель:** Отключить условный переход на адресе **`0x00468648`** в функции `android::CursorInputMapper::sync`, чтобы ротация по `mOrientation` выполнялась и для `mSource == 0x20004`.
```c
00468610        int32_t x9_2 = *(uint32_t*)((char*)this + 0x3c);
00468628        float v0 =
00468628            *(uint32_t*)((char*)this + 0x40) * (float)*(uint32_t*)((char*)this + 0x20);
0046862c        float v1_1 =
0046862c            *(uint32_t*)((char*)this + 0x44) * (float)*(uint32_t*)((char*)this + 0x24);
00468634        float var_1308 = v1_1;
00468634        float var_1304 = v0;
00468634        
00468648        if (x9_2 != 0x20004)
00468648        {
0046864c            int32_t x9_3 = *(uint32_t*)((char*)this + 0x100);
0046864c            
00468654            if (x9_3 == 3)
00468654            {
00468680                var_1304 = -(v1_1);
00468688                var_1308 = v0;
00468654            }
00468654            else if (x9_3 == 2)
0046865c            {
00468670                var_1304 = -(v0);
00468688                var_1308 = -(v1_1);
0046865c            }
0046865c            else if (x9_3 == 1)
00468664            {
00468668                var_1304 = v1_1;
00468688                var_1308 = -(v0);
00468664            }
00468648        }
```

* **Инструкция в Binary Ninja / IDA Pro:**
1. Открыть `/system/lib64/libinputreader.so`.
2. Перейти по адресу **`0x00468648`** (условный переход `b.eq #0x46868c` после сравнения `mSource` с `0x20004`).
3. Заменить инструкцию перехода на **`NOP`** (`1F 20 03 D5` в ARM64).
4. Сохранить модифицированный `libinputreader.so`.

### Вариант Б: Обход на уровне приложения / `framework.jar` (Java/Smali)
Если нет возможности подменить нативную библиотеку, при `motionEvent.getSource() == 0x20004` в методах `getAxisValue(int)` и `getHistoricalAxisValue(int, int)` меняются местами индексы осей `0` (`AXIS_X`) и `1` (`AXIS_Y`):

```java
int axisX = motionEvent.getSource() != 0x20004 ? 27 : 1; // Вместо 0 берется 1 (AXIS_Y)
int axisY = motionEvent.getSource() != 0x20004 ? 28 : 0; // Вместо 1 берется 0 (AXIS_X)
```


## 4. Установка через модуль Magisk
Чтобы не модифицировать системный раздел напрямую, пропатченный `libinputreader.so` устанавливается через overlay-модуль Magisk: `mouse_orientation_fix_k606f_s510234__v1.zip`  
⚠️ Модуль собран только для прошивки `YT-K606F_S510234_231224_ROW`.  
Чтобы не сломать систему, при установке и загрузке, `libinputreader.so` проверяется по md5 хэшу.


## 5. Полезные команды для отладки

* Проверить состояние `CursorInputMapper`, текущую ориентацию и активный `Pointer Capture`:
```bash
adb shell dumpsys input
```

* Найти библиотеку, содержащую маппер (на случай обновлений прошивки):
```bash
adb shell grep -rn "Cursor Input Mapper:" /system/lib64/
```
