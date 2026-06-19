# VPS-WARP

**Cloudflare WARP на вашем VPS без официального клиента.**  
Нативный WireGuard + умный watchdog с авто-ротацией IP. Сделан для работы с Xray-core, Remnawave, 3X-UI и Marzban.

---

## Зачем

Хостинги блокируют, Cloudflare шейпит трафик из датацентров — WARP перестаёт работать. Стандартный `warp-cli` жирный и капризный.

VPS-WARP поднимает туннель через `wg-quick` и ставит systemd-watchdog, который каждые 3 минуты пингует `1.1.1.1`, `8.8.8.8` и `9.9.9.9` через интерфейс. Если пинг упал или хэндшейк не обновлялся больше 3 минут — скрипт сам меняет endpoint на случайный из пула Cloudflare и перезапускает туннель. Тихо, без вашего участия.

---

## Особенности

- **Нативный WireGuard** — никаких проприетарных демонов Cloudflare
- **Авто-ротация IP** — при падении соединения сам находит живой endpoint из пула `162.159.{192,193,195}.x`
- **Изолированная маршрутизация** (`Table = off`) — WARP не трогает основной трафик сервера, только то что вы явно туда направите
- **TCP MSS Clamping** — iptables-правила на `OUTPUT` и `FORWARD`, предотвращают зависания на тяжёлых сайтах
- **Только IPv4** — IPv6-эндпоинты вырезаются из конфига, нет проблем с маршрутизацией у провайдеров
- **Поддержка WARP+** — опционально, ввод лицензионного ключа при установке
- **CLI-утилита** `vps-warp` — статус, трафик, управление

---

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tagashi666/vps-warp/main/warp_install.sh)
```

Запускать от root. Скрипт спросит язык и опционально ключ WARP+.

---

## Управление

| Команда | Описание |
|---|---|
| `vps-warp` | Статус туннеля: IP, endpoint, handshake, трафик |
| `vps-warp start` | Запустить интерфейс |
| `vps-warp stop` | Остановить интерфейс |
| `vps-warp restart` | Перезапустить и сменить endpoint |
| `vps-warp log` | Логи watchdog (история ротации IP) |

---

## Интеграция с Xray

После установки скрипт выведет локальный IP туннеля (вида `172.16.0.x`). Есть два способа направить трафик через WARP.

### Способ 1 — `sockopt.interface` (рекомендуется)

Добавьте в секцию `outbounds`:

```json
{
  "tag": "warp-out",
  "protocol": "freedom",
  "settings": {
    "domainStrategy": "UseIP"
  },
  "streamSettings": {
    "sockopt": {
      "interface": "warp",
      "tcpFastOpen": true
    }
  }
}
```

### Способ 2 — `sendThrough`

Если `sockopt.interface` не поддерживается вашей версией Xray:

```json
{
  "tag": "warp-out",
  "protocol": "freedom",
  "sendThrough": "<LOCAL_WARP_IP>",
  "settings": {
    "domainStrategy": "UseIP"
  }
}
```

`<LOCAL_WARP_IP>` — IP, который вывел скрипт после установки.

### Правило маршрутизации

```json
{
  "type": "field",
  "domain": [
    "geosite:openai",
    "domain:instagram.com",
    "domain:google.com"
  ],
  "outboundTag": "warp-out"
}
```

---

## Как это работает

```
Xray/Sing-box
     │
     │  (трафик для заблокированных доменов)
     ▼
warp (wg-quick интерфейс)
     │
     │  WireGuard UDP
     ▼
162.159.x.x:2408  ←── watchdog меняет endpoint при блокировке
     │
     ▼
Cloudflare WARP → целевой ресурс
```

Watchdog (`warp-watchdog.timer`) срабатывает каждые 3 минуты:
1. Проверяет, активен ли сервис
2. Смотрит возраст последнего handshake
3. Пингует три DNS-резолвера через интерфейс `warp`
4. Если что-то не так — меняет `Endpoint` в `/etc/wireguard/warp.conf` и делает `systemctl restart wg-quick@warp`

---

## Удаление

```bash
systemctl disable --now wg-quick@warp warp-watchdog.timer warp-watchdog.service
rm -rf /opt/vps-warp /etc/wireguard/warp.conf /usr/local/bin/vps-warp
rm -f /etc/systemd/system/warp-watchdog.{service,timer}
systemctl daemon-reload
apt remove --purge -y wireguard
```

---

## Лицензия

MIT — [LICENSE](LICENSE)
