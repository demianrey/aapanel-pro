# aaPanel Pro — Desbloqueado

Todos los plugins desbloqueados, funciones Pro habilitadas, sin verificación de licencia. Compatible con instalaciones nuevas o existentes de aaPanel. Probado en **aaPanel 8.0.5** (última versión disponible).

---

## Instalación rápida (servidor nuevo)

**Paso 1 — Instalar aaPanel** (instalador oficial, solo una vez):
```bash
bash <(curl -s https://www.aapanel.com/script/install_7.0_en.sh)
```
> Anota la URL del panel, puerto, usuario y contraseña que muestra al final.

**Paso 2 — Clonar y aplicar el patch:**
```bash
git clone https://github.com/demianrey/aapanel-pro.git
cd aapanel-pro
bash install.sh
```

**Paso 3 — Instalar software (PHP, Nginx, MySQL, phpMyAdmin, Redis, FTP):**
```bash
bash post_install.sh --all
```

Listo. Entra al panel — todos los plugins aparecerán como Pro, sin botones de compra.

---

## Aplicar patch a aaPanel ya instalado

Si ya tienes aaPanel y solo necesitas activar el unlock:

```bash
git clone https://github.com/demianrey/aapanel-pro.git
cd aapanel-pro
bash patch.sh
```

---

## Qué hace cada script

| Script | Función |
|--------|---------|
| `install.sh` | Aplica todos los patches + copia directorios de plugins. Ejecutar después de instalar aaPanel. |
| `patch.sh` | Patcher principal — detecta los patrones JS en cualquier versión de aaPanel, aplica los cambios y reinicia el panel. |
| `post_install.sh` | Instala PHP 5.6–8.3, Nginx, MySQL 8.0, phpMyAdmin, Redis, Memcached, Pure-FTPd. |

---

## Qué se parchea

### Backend — `patches/PluginLoader.py`

Mock en Python que reemplaza la librería DRM `.so`. En cada request del panel:

- Intercepta `get_plugin_list()` y establece `endtime` a 10 años para todos los plugins
- Devuelve estado Pro/lifetime (`pro = 0`, `ltd = -1`) sin contactar servidores de aaPanel
- Carga el `.so` original como `PluginLoader_real.so` para delegarle la descifración de archivos internos del panel (necesario para que el panel funcione correctamente)
- Intercepta `plugin_run()` saltándose la verificación de auth del `.so`, cargando el plugin directamente
- Devuelve un dict de error seguro (no `None`) cuando un plugin no existe, evitando crashes en el panel

### Frontend — `patches/js/`

El `patch.sh` aplica estos cambios mediante regex (funciona independientemente del hash del bundle):

| Cambio | Descripción |
|--------|-------------|
| Indicador de compra | `isBuy` siempre retorna `false` — elimina botones "Buy now" en el App Store |
| Página de WAF | Muestra siempre el botón **Install**, nunca "Buy now" |

### Plugins — `plugin/`

Stubs y archivos de configuración para los plugins de pago:

`bt_security`, `btapp`, `btwaf`, `btwaf_httpd`, `dns_manager`, `fail2ban`, `jumpserver`, `load_balance`, `mail_sys`, `monitor`, `mysql_replicate`, `nodejs`, `redis`, `rsync`, `ssl_verify`, `syssafe`, `tamper_core`, `tamper_proof`, `task_manager`, `total`

### Archivos `.so` — `so/`

Binarios originales del `PluginLoader` para todas las arquitecturas (usados por el mock para delegar llamadas internas):

| Archivo | Arquitectura |
|---------|-------------|
| `PluginLoader.x86_64.Python3.12.so` | x86_64, Python 3.12 |
| `PluginLoader.x86_64.Python3.7.so` | x86_64, Python 3.7 |
| `PluginLoader.x86_64.glibc214.Python3.7.so` | x86_64, glibc antiguo |
| `PluginLoader.aarch64.Python3.12.so` | ARM64, Python 3.12 |
| `PluginLoader.aarch64.Python3.7.so` | ARM64, Python 3.7 |
| `PluginLoader.i686.Python3.7.so` | x86 32-bit |
| `PluginLoader.loongarch64.Python3.7.so` | LoongArch64 |

---

## Opciones de post_install.sh

```bash
bash post_install.sh --all      # Todo: PHP 5.6–8.3 + Nginx + MySQL + phpMyAdmin + Redis + FTP
bash post_install.sh --stack    # Stack principal: Nginx + MySQL + PHP 5.6–8.3 + phpMyAdmin + Redis
bash post_install.sh --php      # Solo versiones PHP (5.6, 7.0–7.4, 8.0–8.3)
bash post_install.sh --nginx    # Solo Nginx
bash post_install.sh --mysql    # Solo MySQL 8.0
bash post_install.sh --pma      # Solo phpMyAdmin
bash post_install.sh --redis    # Solo Redis
bash post_install.sh --plugins  # Ejecuta install.sh de cada directorio de plugin
```

---

## WAF (Firewall de Aplicaciones Web)

El WAF requiere instalación antes de usarse. Después de aplicar el patch:

1. Ir a **App Store → Security → aaPanel WAF**
2. Hacer clic en **Install** (el patch elimina el botón de compra)
3. Una vez instalado, el overview del WAF es accesible

El WAF funciona en modo stub — muestra la interfaz sin bloquear tráfico real (el motor Lua requiere el plugin de pago). Es suficiente para que el panel no muestre errores.

---

## App móvil (btapp)

Para usar la app aaPanel Mobile:

1. Ir a **App Store → btapp → Settings** — aparecerá un QR para escanear con la app
2. Escanear el QR desde la app → aprobar el binding en el panel
3. Para el login por QR en la pantalla de login del panel, crear el archivo de activación:
   ```bash
   touch /www/server/panel/data/app_login.pl
   bt restart
   ```

---

## Compatibilidad con futuras versiones

| Componente | Robustez | Qué puede romper |
|------------|----------|-----------------|
| `PluginLoader.py` (bypass core) | Alta | Solo si aaPanel cambia completamente su sistema de auth |
| `sitecustomize.py` | Muy alta | Nada — es un hook estándar de Python |
| Patches de JS frontend | Baja | Cada actualización regenera los bundles con nuevos hashes |
| Patches de `panelPlugin.py` | Media | Si aaPanel refactoriza el flujo de instalación de plugins |

**Después de cada actualización de aaPanel**, vuelve a ejecutar:
```bash
cd aapanel-pro
bash patch.sh
```

El script es idempotente — detecta lo que ya está aplicado y solo re-aplica lo necesario.

---

## Cómo funciona el bypass DRM

aaPanel Pro verifica las licencias de plugins a través de `PluginLoader.so`. Este binario:
1. Contacta los servidores de auth de aaPanel para validar la clave de licencia
2. Retorna `endtime = -1` para plugins sin licencia, bloqueando su uso

Nuestro `PluginLoader.py` se carga en su lugar (Python prioriza `.py` sobre `.so` en `sys.path`):
1. Carga el `.so` original como módulo separado (`_real`) sin registrarlo en `sys.modules`, para que el bypass siempre tome prioridad
2. Intercepta `get_plugin_list()` — parchea `endtime` de `-1` a `+10 años`
3. Intercepta `plugin_run()` — carga plugins directamente sin pasar por la verificación de auth del `.so`
4. Delega al `.so` real solo para descifrado de archivos internos del panel (`get_module`)
5. `sitecustomize.py` elimina automáticamente `PluginLoader.so` en cada inicio de Python, evitando que aaPanel lo regenere y sobreescriba el bypass

---

## Sistemas operativos compatibles

| SO | Versiones |
|----|----------|
| Ubuntu | 20.04, 22.04, 24.04 |
| Debian | 10, 11, 12 |
| CentOS | 7, 8 |
| AlmaLinux / Rocky | 8, 9 |

Arquitecturas: `x86_64`, `aarch64` (ARM64)
