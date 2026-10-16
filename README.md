# PSPKVM for iOS (armv7, iOS 7.0+)

Эмулятор **J2ME / MIDP 2.1** (Java ME приложения и игры: `.jar` / `.jad`) для старых iOS-устройств на 32-битных чипах **Apple A5** под управлением **iOS 7.0 и новее**.

Проект — порт [PSPKVM](http://www.pspkvm.org) (который сам основан на Sun/Oracle **phoneME Feature**) на iOS. Виртуальная машина CLDC HI, MIDP, JSR-слои и AMS остались прежними, переписан платформенный слой (`javacall/implementation/ios_arm`) и добавлена нативная оболочка на UIKit (`ios/`).

> Это рабочий порт: версия приложения `0.1`. Исходная кодовая база PSPKVM последний раз выходила в 2011 году (0.5.5).

---

## Целевая платформа

| Параметр | Значение |
|---|---|
| Архитектура | `armv7` (32 бита) |
| Целевой чип | Apple A5 (iPhone 4S, iPad 2, iPad mini 1, iPod touch 5) |
| Минимальная iOS | 7.0 (`MinimumOSVersion`, `--target=armv7-apple-ios7.0`) |
| SDK для сборки | iPhoneOS 9.3 |
| Bundle ID | `com.pspkvm.ios` |
| Устройства | iPhone и iPad (`UIDeviceFamily` 1, 2) |
| Ориентации | портрет, ландшафт (оба) |

Частота кадров экрана ограничена **30 fps** (`CADisplayLink.frameInterval = 2`): для J2ME хватает с запасом и бережёт старое железо.

## Возможности

Наследуются от PSPKVM / phoneME и включены в iOS-сборке (`build-ios-cldc.sh`):

- CLDC 1.1 / MIDP 2.1, многозадачность MIDlet'ов (MVM / isolates)
- Nokia UI API (частично) и расширения PSPKVM (`USE_NOKIA_UI`, `USE_PSPKVM_EXT`)
- JSR 75 — File Connection
- JSR 135 — Mobile Media API (MIDI / WAV / MP3)
- JSR 120 — Wireless Messaging (заглушка)
- JSR 172 — Web Services
- JSR 226 — SVG (Pisces)
- JPEG, TrueType-шрифты через FreeType
- Виртуальная клавиатура (`SOFT_KEYBOARD_ENABLED`)
- Эмуляция устройства: выбор размера экрана и раскладки клавиш

Отключено в iOS-сборке: **JSR 179 (GPS)**.

## Установка

Сборка CI выдаёт два артефакта в `ios/packages/`:

- `PSPKVM-<commit>-armv7-iOS7.ipa`
- `.deb` (для джейлбрейкнутых устройств; `postinst` вызывает `uicache`)

**Джейлбрейк:** установи `.deb` через Cydia/Filza/`dpkg -i`.

**Без джейлбрейка:** установи `.ipa` через стороннюю установку (Cydia Impactor, AltStore, Sideloadly и т.п.). Бинарник собирается через Theos без сертификата разработчика (`CODESIGN_FLAGS` пуст), поэтому на устройстве его нужно подписать своим Apple ID или использовать твик, отключающий проверку подписи.

## Запуск MIDlet'ов

В `Info.plist` включён `UIFileSharingEnabled`, поэтому файлы можно закидывать через iTunes / Finder → «Общие файлы». Рабочая папка приложения:

```
Documents/pspkvm/
├── lib/              # ромизированные классы, шрифты (пересоздаётся при смене версии сборки)
├── appdb/            # установленные MIDlet'ы и RMS (сохраняется при обновлениях)
├── root/             # сюда кладём .jar / .jad
├── pspkvm.ini        # настройки (создаётся один раз)
└── vmsettings.cfg    # настройки VM (создаётся один раз)
```

1. Положи `.jar` / `.jad` в `Documents/pspkvm/root/`.
2. Запусти приложение. Через AMS выбери «Find Application» и установи файл из каталога `root`.
3. Дальше MIDlet запускается прямо из списка AMS.

> Пункты меню AMS унаследованы от PSPKVM. Если названия в iOS-сборке отличаются, ориентируйся на меню приложения.

## Управление

Экранная панель в стиле PSP (мультитач):

- **Портрет:** экран игры сверху, панель кнопок снизу.
- **Ландшафт:** экран на весь дисплей, панель полупрозрачно наложена снизу.

Кнопки: D-pad, `△ ✕ □ ○`, `L`, `R`, `SELECT`, `START`. Касание по самому экрану передаётся как pen/touch-событие.

Раскладка кнопок → клавиши телефона наследуется от PSPKVM:

| Телефон | Кнопка панели |
|---|---|
| `0` | ✕ |
| `1` | □ |
| `2` / `4` / `6` / `8` | ↑ / ← / → / ↓ |
| `3` | △ |
| `5` | Shift + ○ |
| `7` | Shift + □ |
| `9` | Shift + △ |
| `*` | Shift + SELECT |
| `#` | Shift + START |
| Левая / правая софт-клавиша | SELECT / START |
| Select (OK) | ○ |

`Shift` = удерживаемые `L` или `R`.

Горячие комбинации (из PSPKVM):

- `L + R + △` — свернуть MIDlet в фон и вернуться в AMS
- `L + R + ✕` — завершить текущий MIDlet

Раскладку клавиш можно менять для каждого приложения: выбери MIDlet в AMS → «Select Device».

## Настройки

`Documents/pspkvm/pspkvm.ini` — основной файл настроек. Размер шрифтов, виртуальная клавиатура и раскладка настраиваются из GUI: `System midlets → Configure VM`.

Пути JSR 75 (File Connection) задаются в секции `[jsr75]`. В iOS-порте «хвосты» от PSP вида `ms0:` в старом `pspkvm.ini` распознаются и игнорируются, так что корректнее оставить значения пустыми.

## Сборка из исходников

Сборка выполняется **кросс-компиляцией на Linux** (Ubuntu 24.04, glibc ≥ 2.38). Полный воспроизводимый рецепт — в [`.github/workflows/ios.yml`](.github/workflows/ios.yml). Кратко:

### Требования

- [Theos](https://theos.dev) + vanilla-clang тулчейн для iOS (L1ghtmann/llvm-project, поддерживает 32-битный ARM)
- iPhoneOS **9.3** SDK (с armv7-слайсами; для clang 19 `module.map` нужно переименовать в `module.modulemap`)
- Исправленный `__config_site` для libc++ из тулчейна (шаг есть в CI)
- **FreeType 2.13.2**, собранный под `armv7-apple-ios7.0` и положенный в SDK
- **JDK 8 или старше** (CLDC preverifier требует class-файлы уровня 1.3)
- 32-битные хост-тулзы: `gcc-multilib`, `g++-multilib` (для `romgen` / `loopgen`)
- `perl`, `make`, `zip`, `fakeroot`, `autoconf`, `automake`, `libtool`

### Шаги

```sh
export THEOS=/path/to/theos
export JDK_DIR=/path/to/jdk8
# опционально:
#   IOS_SDK=$THEOS/sdks/iPhoneOS9.3.sdk   IOS_MIN=7.0
#   IOS_CC / IOS_CXX / IOS_AR / IOS_FREETYPE_INC

# 1. Библиотеки VM: javacall + pcsl + cldc + midp
./build-ios-cldc.sh

# 2. Приложение (.app + .deb) через Theos
cd ios
make -f Makefile package FINALPACKAGE=1 SDK_ROOT="$THEOS/sdks/iPhoneOS9.3.sdk"
```

Флаги `build-ios-cldc.sh`:

| Флаг | Назначение |
|---|---|
| `-C` | clean перед сборкой |
| `-e` | только очистка |
| `-d` | debug-сборка |
| `-p` / `-j` / `-c` / `-m` | собрать только pcsl / javacall / cldc / midp |
| `-J <dir>` | путь к JDK |
| `-r <dir>` | корень дерева исходников |

Скрипт складывает статические библиотеки (`libmidp`, `libjavacall`, `libcldc_vm`, `libpcsl_*`) и рантайм-дерево в `build-ios/dist/`, откуда их забирает `ios/Makefile`.

Итоговый `.ipa` упаковывается из `ios/.theos/_/Applications/pspkvm.app` в `Payload/` (см. шаг «Pack .ipa» в workflow).

### CI

GitHub Actions workflow **«PSPKVM iOS armv7 (J2ME emulator, iOS 7.0+)»** запускается при изменениях в `ios/`, `javacall/`, `cldc/`, `midp/`, `pcsl/`, `jsr135/`, `ext/`, `build-ios-cldc.sh` и вручную (`workflow_dispatch`). Он также проверяет, что бинарник не импортирует классы, которых нет в iOS 7 (`UIAlertController`, `CAMetalLayer`, `UIStackView`, `UIVisualEffectView`), и в этом случае падает.

## Структура репозитория

| Путь | Что внутри |
|---|---|
| `ios/` | Нативная оболочка (UIKit): `KVMAppDelegate`, `KVMBridge` (песочница, поток VM), `KVMScreenView` (вывод кадра), `KVMPadView` (экранный геймпад), `Info.plist`, Theos `Makefile`, `layout/DEBIAN` |
| `javacall/implementation/ios_arm/` | Платформенный слой javacall для iOS (LCD, ввод, звук, сеть, файлы, шрифты) |
| `cldc/` | Виртуальная машина CLDC HI |
| `midp/` | Реализация MIDP, AMS, приложения |
| `pcsl/` | Portable Common Services Library |
| `jsr75/`, `jsr120/`, `jsr135/`, `jsr172/`, `jsr179/`, `jsr226/` | Опциональные пакеты JSR |
| `ext/` | Nokia UI и расширения PSPKVM |
| `pisces/`, `jpeg/`, `restricted_crypto/` | SVG-рендер, JPEG, криптография |
| `midlets/` | Тестовые MIDlet'ы и скрипты для сборки своих |
| `psp/` | Исходный PSP-порт (для справки; здесь используется `pspkvm.ini`) |
| `art/` | Исходники графики виртуальных клавиатур |
| `tools/` | Вспомогательные инструменты |
| `build-ios-cldc.sh` | Сборка библиотек VM под iOS |
| `build-psp-cldc.sh`, `build-win32-cldc.sh` | Сборка под PSP и Windows (наследие) |

## Известные ограничения

- Только 32-битный `armv7`. На 64-битных устройствах и в новых версиях iOS (где 32-битные приложения не запускаются) работать не будет.
- Приложение не подписано сертификатом разработчика (см. «Установка»).
- JSR 179 (GPS) выключен.
- Наследуемые проблемы PSPKVM: `javacall_file_truncate` не портирован (часть операций усечения файлов, в том числе в RMS, может работать некорректно); `rmdir` в File Connection иногда завершается ошибкой.
- Временные мультимедийные файлы (`*_tmp_mus.mid`) могут остаться после падения VM.
- Графика не оптимизирована (в TODO оригинального проекта: «Graphic optimization», JSR 184, MIPS JIT).

## Благодарности и лицензия

- **PSPKVM**: Sleepper, M@x, Anweifeng, AJ Milne; тестирование: Jurgen Konings — [pspkvm.org](http://www.pspkvm.org), [SourceForge](http://sourceforge.net/projects/pspkvm)
- **phoneME Feature** (Sun Microsystems / Oracle) — основа VM и MIDP
- **FreeType**, **libjpeg**, **Theos** и тулчейн L1ghtmann

Исходный код наследует лицензии phoneME и PSPKVM (в основном GPLv2 с Classpath exception для phoneME). Файла с общей лицензией в корне репозитория нет, поэтому перед публикацией добавь `LICENSE` и проверь лицензии вложенных компонентов.

Оригинальная документация PSPKVM: [`Readme.txt`](Readme.txt), [`BUILDING.TXT`](BUILDING.TXT), [`CHANGELOG.TXT`](CHANGELOG.TXT).
