<!-- synced-from: ae5c87b3d094be05e291c31c900894e8b3705db2 -->
# NotebookLM KB System — un "segundo cerebro" eficiente en tokens para agentes de IA

**English**: [README.md](README.md) · [Español](README.es.md)

> **Resumen — ¿qué es esto?** El **NotebookLM KB System** es un flujo de trabajo autoalojable
> sobre la **CLI de NotebookLM** que le da a un agente de IA un segundo cerebro persistente y
> **eficiente en tokens**: una memoria local diminuta que se carga en cada sesión, más un corpus
> grande en NotebookLM que se consulta bajo demanda. En corto: **memoria práctica para agentes de
> IA** que puede **reducir el coste en tokens** de una investigación amplia y multifuente en
> **~99% de los tokens de salida facturados al agente — en una comparación documentada** (n = 1; ver *Ahorro de tokens*) frente a un rastreo web con múltiples agentes.

Una base de conocimiento pequeña y autoalojable que permite a un agente de IA **recordar mucho
cargando casi nada** en cada sesión. Es un **segundo cerebro para agentes LLM** con dos almacenes
de escritura y un no-almacén deliberado:

- **Memoria local** — un puñado de ficheros Markdown cortos, que entran en el contexto del agente
  en *cada* ejecución. Pequeña a propósito (la pagas en tokens todas las sesiones).
- **Cuadernos de NotebookLM** — un corpus de referencia grande que se **consulta bajo demanda** en
  lugar de cargarse. Mantenerlo grande sale gratis; solo cuesta tokens cuando preguntas.
- **Un cubo de descarte** — datos vivos y perecederos (% de disco, IPs, tokens, "¿está el servicio
  levantado?") que **nunca se escriben** y se vuelven a verificar contra el sistema cuando hacen falta.

Lo que lo une todo es una **regla de enrutado a 3 destinos** (INTERNA / EXTERNA / NINGUNO) que
decide dónde va cada aprendizaje nuevo, y un paso de **investigación web** que descarga el
descubrimiento amplio en la propia infraestructura de NotebookLM — de forma que el agente paga por
un resultado compacto, no por leerse medio internet.

> **Nota de idioma:** este README está en español; los manuales de `docs/`, las guías de
> instalación, los scripts y sus mensajes están en inglés.

> Todo en este repositorio es genérico. Cada email, ID, ruta y nombre es un marcador de posición
> (`<YOUR_EMAIL>`, `<NOTEBOOK_ID>`, `<YOUR_PROJECT>`, `~/.kb/`). No pongas secretos reales aquí.

---

## 1. Qué es esto

Un agente de IA tiene una ventana de contexto fija y cara. Dos malas costumbres la desperdician:

1. **Cargarlo todo por adelantado** — volcar un wiki entero en el prompt "por si acaso".
2. **Volver a derivar el conocimiento cada sesión** — releer los mismos documentos grandes, o
   rehacer un reconocimiento web amplio desde cero, una y otra vez.

Este sistema arregla las dos:

- **Carga solo lo que necesitas saber *antes* de poder actuar** — identidad, reglas duras,
  correcciones de método y un puntero a lo que está en marcha. Eso es la **memoria local**. Se
  mantiene corta para que el impuesto en tokens por sesión sea mínimo.
- **Todo lo demás es referencia** — arquitectura, procedimientos, sintaxis de comandos, gotchas,
  callejones sin salida, diseño estable. Eso va a los **cuadernos de NotebookLM** y solo entra
  cuando una tarea lo necesita de verdad, de una respuesta fundamentada en cada vez.
- **El descubrimiento se descarga fuera.** Cuando necesitas investigación amplia y multifuente, el
  flujo **add-research** de NotebookLM ejecuta la búsqueda y la ingesta en la infraestructura de
  Google. El agente luego lee una síntesis compacta y con citas —unos pocos miles de tokens— en
  lugar de soltar un enjambre de subagentes que queman tokens rastreando la web. (Ver la sección
  de ahorro de tokens para los números.)

El resultado es un "segundo cerebro" barato de llevar encima, profundo de consultar y honesto
sobre lo que no sabe.

---

## 2. Arquitectura

Tres destinos, una decisión de enrutado, dos caminos de consulta.

```
                          UN APRENDIZAJE NUEVO
                                  │
                    ┌─────────────┼──────────────┐
                    ▼             ▼               ▼
                INTERNA        EXTERNA         NINGUNO
             (memoria local) (cuaderno NB)    (descartar)
             ─────────────   ─────────────   ─────────────
             identidad       referencia      estado vivo:
             reglas duras    procedimientos  % disco, IPs,
             fixes de metodo comandos        contadores,
             WIP abierto     gotchas         tokens,
                             callejones      versiones,
                             diseno estable  "esta levantado?"
             ─────────────   ─────────────   ─────────────
             SE CARGA cada   SE CONSULTA     NUNCA se guarda:
             sesion          bajo demanda    se verifica en
             (mantener corta)(mantener grande) el sistema vivo


        CAMINO DE LECTURA (barato, comun)   CAMINO DE ESCRITURA (hacer crecer el corpus)
        ─────────────────────────           ────────────────────────────
        agente ── pregunta ──▶ NotebookLM   editar build-doc ──▶ source add
                 ◀── respuesta fundamentada              ──▶ esperar "ready"
                     (pocos miles de tokens)             ──▶ borrar fuente vieja

                              research.sh <ID> "<consulta>" fast|deep
                                          │
                                          ▼
                    NotebookLM ejecuta busqueda+ingesta en infra de Google
                                          │
                                          ▼
                    el agente lee el resultado compacto (~pocos miles de tokens)
```

- **INTERNA** vive en `~/.kb/memory/` (ver [plantilla de memoria](docs/MEMORY.template.md)).
- **EXTERNA** vive en NotebookLM; un pequeño `notebooks.json` mapea claves legibles → ids.
- **NINGUNO** no vive en ningún sitio — se verifica contra el sistema (`df`, `ip a`,
  `systemctl status`, la API) en el momento en que lo necesitas.

La regla completa, con ejemplos resueltos, está en
[Knowledge routing](docs/KNOWLEDGE-ROUTING.md).

---

## Inicio rápido

1. **Elige la guía de tu terminal** en [Instalación](#instalación) más abajo — o ejecuta directamente el instalador automático.
2. **Ejecuta el instalador** (necesita Python 3.10+): `bash install/install.sh` (Linux/macOS) o `install/install.ps1` (Windows/PowerShell). Construye el entorno virtual `~/.kb/venv` (en Windows: `$HOME\.kb\venv`), instala la CLI y detecta tu navegador automáticamente.
3. **Inicia sesión una vez:** `notebooklm login` — deja sembrada en esta máquina una sesión reutilizable y apta para modo headless.
4. **Primera investigación:** `~/.kb/research.sh <NOTEBOOK_ID> "<una pregunta extensa y con contexto>" fast`.

---

## Instalación

> ### Lee esto antes de instalar
>
> **Este kit maneja una CLI no oficial.** Está construido sobre
> [`notebooklm-py`](https://pypi.org/project/notebooklm-py/), de Teng Lin, un proyecto
> comunitario que automatiza una sesión de navegador contra NotebookLM. **No** es un producto
> de Google, no hay una API soportada por detrás, y ni este repositorio ni `notebooklm-py`
> están afiliados a Google ni respaldados por Google.
>
> *Nota fechada, 2026-09-23.* Dos cosas se han movido alrededor del párrafo anterior sin cambiarlo:
>
> - **El producto se llama ahora Gemini Notebook.** Google renombró NotebookLM a Gemini Notebook el
>   2026-07-16, «el mismo producto independiente»; los cuadernos compartidos y los enlaces existentes
>   siguen funcionando mediante redirecciones automáticas (Fuente: [blog.google](https://blog.google/innovation-and-ai/products/gemini-notebook/notebooklm-gemini-notebook/),
>   [Google Workspace Updates](https://workspaceupdates.googleblog.com/2026/07/notebooklm-now-gemini-notebook.html)). Este repositorio, el paquete `notebooklm-py`
>   y el comando `notebooklm` conservan el nombre antiguo.
> - **«No hay una API soportada» es cierto del producto de consumo que maneja este kit.** Google Cloud
>   publica una API en vista previa (términos Pre-GA) para *Gemini Notebook Enterprise* que cubre
>   cuadernos, fuentes y resúmenes de audio; sus páginas documentadas no contienen ninguna operación
>   de pregunta/chat a 2026-09-23, así que no sustituye a la CLI de sesión de navegador para la ruta de
>   lectura de este kit (Fuente: API de Gemini Notebook Enterprise, [cuadernos](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks) y
>   [fuentes](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks-sources), ambas «Last updated 2026-09-22 UTC»). La ausencia de un endpoint
>   de consulta es una observación de esas páginas, no una afirmación de Google.
>
> Lo que se sigue de eso, en la práctica:
>
> - **Google puede romperlo sin avisar.** Basta con un cambio en la aplicación web de
>   NotebookLM. Cuando pasa, el arreglo está aguas arriba, no aquí.
> - **La autenticación es una sesión de navegador, no un token.** Caduca a su propio ritmo y
>   puede fallar *en silencio*: `doctor` y `auth check` dicen "válida" mientras todas las
>   llamadas reales fallan. Para eso existe `healthcheck.sh`. Ver
>   [docs/AUTH-RESILIENCE.md](docs/AUTH-RESILIENCE.md).
> - **Todo lo que pongas en un cuaderno va a Google.** Eso es el diseño, no una fuga. Un
>   cuaderno es material de referencia, nunca una caja fuerte — ver [Seguridad](#seguridad).
> - **Trátalo como un laboratorio, no como infraestructura.** Es útil y está probado, pero no
>   pongas en su camino crítico nada que no puedas hacer a mano.
>
> Las notas de riesgo completas están en [docs/FAQ.md](docs/FAQ.md) y
> [SECURITY.md](SECURITY.md).

Dos formas de instalar: un **script automático**, o una **guía paso a paso** para tu terminal.

### Scripts automáticos

- **Linux / macOS** → [`install/install.sh`](install/install.sh): `bash install/install.sh`
- **Windows (PowerShell)** → [`install/install.ps1`](install/install.ps1)

Los dos scripts crean el entorno virtual (`~/.kb/venv`, en Windows `$HOME\.kb\venv`), instalan
la CLI con sus extras de navegador (`notebooklm-py[browser,cookies]>=0.8.2,<0.9`) y **detectan un
navegador que ya tengas** (Chrome / Chromium / Edge / Brave / Firefox); solo si no encuentran
ninguno descargan el Chromium de Playwright. No crean los ficheros de configuración de `~/.kb/` —
los pasos siguientes que imprimen explican cómo. En un servidor Linux recién montado, ejecuta
además `sudo ~/.kb/venv/bin/playwright install-deps chromium`
([install/linux.md §4](install/linux.md)).

### Guías paso a paso

¿Prefieres ejecutar cada paso tú, o necesitas diagnosticar un problema? Sigue la guía de tu terminal:

- [Windows (PowerShell)](install/windows-powershell.md)
- [Windows (CMD)](install/windows-cmd.md)
- [Linux](install/linux.md)
- [macOS](install/macos.md)

---

## Compatibilidad y qué está realmente probado

### Versiones

| Componente | Soportado | Notas |
|---|---|---|
| `notebooklm-py` | **`>=0.8.2,<0.9`** | Fijado. La 0.8.2 cambió la forma de la CLI que maneja este kit; el límite superior es deliberado, no pereza. |
| Python | **3.10+** | `notebooklm-py` declara `Requires-Python >=3.10`; el instalador rechaza versiones anteriores. |
| Linux | soportado | Instalador + [guía](install/linux.md). En un servidor recién montado, ejecuta además `playwright install-deps chromium`. |
| macOS | soportado | Instalador + [guía](install/macos.md). Usa las alternativas BSD donde las herramientas GNU difieren. |
| Windows | soportado | Guías de [PowerShell](install/windows-powershell.md) y [CMD](install/windows-cmd.md), más `install/install.ps1`. |
| Navegadores | Chrome · Chromium · Edge · Brave · Firefox | Cualquiera que ya tengas. El Chromium de Playwright solo se descarga si no hay ninguno. |

**Cuando `notebooklm-py` publique la 0.9**, este kit no la sigue automáticamente. El pin hay que
subirlo a propósito, después de comprobar que la forma de la CLI de la que dependen los scripts no
ha vuelto a cambiar — que es justo la razón por la que el pin existe.

*Notas fechadas, 2026-09-23:*

- La 0.8.2, publicada el 2026-09-02, es la última `notebooklm-py` en PyPI, así que el pin
  `>=0.8.2,<0.9` resuelve hoy a exactamente una versión; `Requires-Python` sigue siendo `>=3.10`
  (Fuente: [JSON de PyPI para notebooklm-py](https://pypi.org/pypi/notebooklm-py/json)).
- La rama `main` de aguas arriba ya etiqueta su trabajo no publicado como v0.9: la sección Unreleased
  de su changelog marca `client.rpc_call(...)` como obsoleto «in v0.9.0 for removal in v1.0» y hace
  que el `source_add` por ruta de host del MCP stdio sea denegado por defecto (Fuente: [CHANGELOG de
  notebooklm-py, Unreleased](https://github.com/teng-lin/notebooklm-py/blob/main/CHANGELOG.md), leído el 2026-09-23). El pin excluirá por tanto la
  siguiente versión de aguas arriba por diseño; el bloque de pruebas con la CLI real tiene que pasar
  contra la 0.9 antes de moverlo.
- Python 3.10 llega a su fin de vida en octubre de 2026 (Fuente: [Python Developer's Guide,
  versions](https://devguide.python.org/versions/)). El mínimo 3.10 es una declaración de aguas arriba, no una elección de
  este kit; cuando aguas arriba lo suba, la comprobación del instalador lo seguirá.

### Qué cubren las pruebas y qué no

`bash tests/run.sh` → **21 pasadas, 1 saltada** en una máquina limpia.

| Cubierto sin red y sin cuenta | Cómo |
|---|---|
| Los cuatro scripts parsean | `bash -n` |
| El manejo de argumentos de `research.sh`, sus modos, y la invocación exacta de la CLI que construye | un **`notebooklm` simulado** en `tests/bin` registra con qué se le llamó |
| Que una consulta con pinta de flag (`--help`) se pasa como consulta y no se parsea como flag | el mismo simulador |
| La clasificación de fallos de `healthcheck.sh`, incluido el sobre `AUTH_REQUIRED` | el mismo simulador |

Eso es lo que CI ejecuta en cada push, y no necesita **ni cuenta de Google ni credenciales** — que
es justo la idea: una suite que exigiera una sesión viva no podría ejecutarse en CI.

| **No** cubierto automáticamente | Por qué |
|---|---|
| Que la CLI real siga aceptando los comandos que construyen estos scripts | Necesita `notebooklm-py` instalado. El arnés *sí* lo prueba — `NOTEBOOKLM_REAL_CLI=/ruta/al/venv/bin/notebooklm bash tests/run.sh` ejecuta cinco comprobaciones extra que llegan hasta la puerta de autenticación y verifican que no hay errores de parseo — pero se salta cuando el binario no está, que es la `1 saltada` de arriba. |
| Que NotebookLM en sí siga comportándose igual | No hay API, no hay contrato. Solo observación. |
| El login, la renovación de sesión y las investigaciones reales | Requieren una sesión de Google real. `healthcheck.sh` existe precisamente porque estas cosas fallan *en silencio*. |

**Ejecuta el bloque saltado antes de fiarte de una actualización.** Es la única comprobación que
detecta el fallo que este kit ya ha sufrido: los scripts llamando a una forma de CLI que ya no existe.

---

## Documentación

Los manuales detallados viven en [`docs/`](docs/):

- [Operations](docs/OPERATIONS.md) — el runbook completo: arquitectura, caminos de lectura y
  escritura, la regla de re-subida add→wait→delete, autenticación headless para deep research,
  gotchas conocidos y una lista de mantenimiento.
- [Knowledge routing](docs/KNOWLEDGE-ROUTING.md) — la regla central de 3 destinos
  (INTERNA / EXTERNA / NINGUNO): qué va dónde, cómo partir aprendizajes mixtos y la regla de
  un-hecho-una-casa, con una lista de decisión.
- [Research prompt template](docs/RESEARCH_PROMPT_TEMPLATE.md) — patrones de prompt para las dos
  operaciones: cómo escribir consultas específicas de add-research y cómo endurecer los prompts de
  `ask` para que no se pierda nada en silencio (respuestas numeradas, un token `NOT IN SOURCES`
  obligatorio, una sección `GAPS` al final).
- [Memory template](docs/MEMORY.template.md) — una plantilla lista para rellenar del índice de
  memoria local que se carga cada sesión: formato del frontmatter, tipos de memoria, índice de una
  línea por entrada y `[[enlaces cruzados]]`.
- [FAQ](docs/FAQ.md) — el FAQ ampliado: qué es esto, cómo lanzar investigación web desde la CLI,
  cuánto ahorra, uso headless y en servidor, y cuándo *no* recurrir a NotebookLM.
- [Auth resilience](docs/AUTH-RESILIENCE.md) — evitar que la autenticación por sesión de navegador
  falle en silencio. Por qué un keepalive frecuente por sí solo **no** evita la muerte a los pocos
  días (tokens ligados al dispositivo), la prevención real (ejercitar el perfil con un navegador de
  verdad o una clave de dispositivo local al host), un healthcheck de operación real que te avisa
  por email, un wrapper endurecido, un modo degradado local, y por qué *no* usar un token maestro
  de Google.

---

## Estructura del proyecto

```
notebooklm-kb-system/
├── README.md                        # este hub: concepto, enlaces, cuentas de tokens, seguridad
├── research.sh                      # wrapper de investigacion web: research.sh <NOTEBOOK_ID> "<consulta>" fast|deep
├── healthcheck.sh                   # healthcheck de auth + aviso por email (ver docs/AUTH-RESILIENCE.md)
├── LICENSE                          # AGPL-3.0-or-later
├── tests/
│   ├── run.sh                       # bash tests/run.sh — pruebas de comportamiento de ambos scripts
│   └── bin/notebooklm               # simulador estricto de la superficie CLI de notebooklm-py 0.8.2
├── install/
│   ├── install.sh                   # instalador automatico (Linux / macOS)
│   ├── install.ps1                  # instalador automatico (Windows / PowerShell)
│   ├── windows-powershell.md        # guia manual — Windows PowerShell
│   ├── windows-cmd.md               # guia manual — simbolo del sistema de Windows
│   ├── linux.md                     # guia manual — Linux (Ubuntu/Debian, bash)
│   └── macos.md                     # guia manual — macOS (zsh)
└── docs/
    ├── OPERATIONS.md                # runbook de operaciones completo
    ├── KNOWLEDGE-ROUTING.md         # la regla de enrutado a 3 destinos
    ├── RESEARCH_PROMPT_TEMPLATE.md  # patrones de prompt para add-research y ask()
    ├── MEMORY.template.md           # plantilla del indice de memoria local
    ├── FAQ.md                       # FAQ ampliado
    └── AUTH-RESILIENCE.md           # evitar que la auth por sesion falle en silencio
```

**Pruebas:** `bash tests/run.sh` (necesita `bash` y `jq`, sin red) maneja `research.sh` y
`healthcheck.sh` contra un simulador estricto de la CLI —conteo antes/después, sondeo, timeouts,
la cascada de aviso/enfriamiento/reautenticación— y comprueba que los scripts llaman a la CLI con
la forma que acepta notebooklm-py 0.8.2. Apunta `NOTEBOOKLM_REAL_CLI` a una instalación de
notebooklm-py (o ten `notebooklm` en el `PATH`) y ejecuta además los mismos comandos contra la CLI
real con un `HOME` vacío: tienen que fallar por autenticación (rc 1), nunca por parseo de
argumentos (rc 2).

---

## Ahorro de tokens (el objetivo de todo esto)

La razón para enrutar el descubrimiento por NotebookLM en vez de por un rastreo multiagente dentro
del propio agente es el coste. La parte cara de una investigación amplia es la **generación**: cada
subagente que lee páginas y escribe notas factura tokens de salida. NotebookLM mueve ese paso
entero de buscar-y-resumir a la **infraestructura de Google**: las llamadas `add-research` y `ask`
le cuestan al agente ~**0 tokens** ejecutarlas, y el agente solo paga por leer el resultado
compacto que vuelve.

### La comparación

| | Reconocimiento amplio vía NotebookLM | Reconocimiento amplio vía un enjambre multiagente |
|---|---|---|
| Dónde se ejecuta el rastreo y el resumen | Infraestructura de Google (fuera de tu presupuesto de tokens) | Tu modelo — cada subagente factura tokens de salida |
| Tokens del agente por investigación | **~unos pocos miles** (leer el resultado) | **~1,9M tokens de salida** (medido, un fan-out real de 52 agentes) |
| Latencia | minutos (asíncrono) | minutos (en paralelo) |
| Qué obtienes | una síntesis fiel y con citas del corpus | un informe sintetizado |

Para ese reconocimiento amplio: **1,9M → ~5K tokens de agente, en torno a un 99% de reducción — medido una vez.**

**Qué es ese número, y qué no es.** Es una tarea, ejecutada una vez, contando solo los tokens de salida facturados al agente; el cómputo propio de NotebookLM no se cuenta, las dos salidas no se puntuaron por calidad equivalente, y la variabilidad entre ejecuciones no se midió. Es una observación documentada, no una tasa. Un benchmark pequeño —corpus, pregunta, salidas redactadas, contador de tokens, denominador, repeticiones, criterios de calidad— es el siguiente paso honesto; hasta que exista, la cifra se lee como *lo que pasó una vez*.

### Cuentas aproximadas por investigación y por mes

Ilustrativas, para dar el orden de magnitud (mete tus propias tarifas):

- **Por investigación amplia:** ~5K tokens (camino NotebookLM) frente a ~1,9M tokens (camino enjambre).
- **~20 reconocimientos amplios al mes:** ~0,1M tokens frente a ~38M tokens — una diferencia de
  aproximadamente **~37,9M tokens/mes** — *si* esa única comparación fuera representativa, cosa que no se ha comprobado. Es aritmética sobre n = 1, mostrada para dar la escala, no un ahorro mensual que nadie haya medido.

El ahorro se acumula también cada vez que *vuelves a consultar* el corpus: un `ask` contra un
cuaderno existente es para siempre una lectura de unos pocos miles de tokens, frente a rehacer el
reconocimiento entero.

### Advertencias honestas — es un híbrido, no una bala de plata

Esta ventaja es real pero **estrecha**. No la vendas de más.

- **Solo para reconocimiento amplio y multifuente.** Para un dato suelto del que ya sabes dónde
  está, una consulta directa es más barata y más rápida que lanzar una investigación. NotebookLM
  compensa cuando, si no, tendrías que abrirte en abanico entre muchas fuentes.
- **La calidad es fidelidad al corpus, no verdad verificada.** NotebookLM fundamenta las respuestas
  en las fuentes que le diste. Si una fuente está equivocada, desactualizada o sesgada, la respuesta
  está equivocada con la misma seguridad. Fundamentar no es verificar.
- **La latencia es de minutos.** La investigación es asíncrona; no es una búsqueda interactiva.

Así que úsalo como una **tubería, no como un sustituto del criterio**:

```
NotebookLM  →  descubrimiento + primera sintesis (barata, fiel, con huecos marcados)
   el agente  →  verificar las afirmaciones que sostienen la decision + razonar + decidir
                 (la parte cara, mantenida pequena)
```

NotebookLM hace la recolección amplia y barata; el agente gasta su (ya pequeño) presupuesto de
tokens en la parte que de verdad necesita una cabeza: contrastar contra una segunda fuente las
afirmaciones que sostienen la decisión, y decidir qué hacer. Ver
[Research prompt template §3](docs/RESEARCH_PROMPT_TEMPLATE.md) para saber exactamente qué trabajos
hay que dejar del lado del agente (valorar fuentes, verificar la verdad, modelar escenarios,
sostener estado vivo).

---

## Seguridad

Esto es una base de conocimiento, y las bases de conocimiento se filtran si las dejas.

- **Nunca pongas secretos en un cuaderno.** Tokens, claves, contraseñas, credenciales de sesión —
  nada de eso pertenece a un documento fuente. El contenido de un cuaderno es referencia, no una
  caja fuerte. Si un procedimiento necesita un secreto, escribe "sácalo de `<almacén de secretos>`",
  no el secreto.
- **Nunca subas secretos a este repositorio.** Cada email, IP, id de cuaderno, ruta y nombre de
  estos ficheros es un **marcador de posición** deliberado (`<YOUR_EMAIL>`, `<NOTEBOOK_ID>`,
  `~/.kb/`, `<YOUR_PROJECT>`). Guarda tus valores reales en tu instalación local de `~/.kb/` y en
  una configuración ignorada por git — no en nada que publiques.
- **El estado vivo no se guarda de todos modos.** El cubo NINGUNO ya mantiene tokens, IPs y estado
  de servicios fuera de ambos almacenes por diseño — verifícalos contra el sistema en el momento de
  usarlos.
- **Mantén `notebooks.json` y el perfil de autenticación en local.** El mapa clave→id y el perfil de
  navegador que siembra `notebooklm login` son locales a la máquina; no los subas ni los compartas.
- **Barre antes de publicar.** Haz grep en el árbol buscando emails, direcciones IPv4, cadenas con
  pinta de token (`ghp_`, `sk-`, `AIza`, `xox`, `key`) y UUIDs antes de subir nada público.

---

## Preguntas frecuentes

Respuestas cortas abajo; el [FAQ ampliado](docs/FAQ.md) tiene el detalle.

**¿Qué es el NotebookLM KB System?**
Es un flujo de trabajo autoalojable sobre la CLI de NotebookLM que le da a un agente de IA (o LLM)
un "segundo cerebro" persistente. El agente carga una memoria local diminuta en cada sesión y
consulta un corpus grande de NotebookLM solo cuando una tarea lo necesita — así recuerda mucho
pagando casi ningún impuesto en tokens por sesión.

**¿Cómo hago investigación web con NotebookLM desde la CLI?**
Ejecuta `~/.kb/research.sh <NOTEBOOK_ID> "<una pregunta extensa y con contexto>" fast` (o `deep`).
NotebookLM hace la búsqueda y la ingesta en la infraestructura de Google y guarda los resultados
como fuentes en el cuaderno; el wrapper vuelve a listar las fuentes para *verificar* que la
importación ocurrió de verdad (nunca se fía del código de salida). Luego lees el resultado con
`notebooklm ask -n <NOTEBOOK_ID> "<pregunta>"` o
`notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>`.

**¿Cuánto puede ahorrar frente a un flujo de investigación multiagente?**
En la única comparación medida, **~99% de los tokens de salida facturados al agente**. Un fan-out de 52 agentes costó
unos **1,9M tokens de salida**; el mismo descubrimiento enrutado por NotebookLM le cuesta al agente
solo unos pocos miles de tokens leer el resultado compacto y citado — porque el rastreo y el resumen
se ejecutan del lado de Google, fuera del presupuesto de tokens del agente.

**¿Funciona en headless / en un servidor?**
Sí. Tras un `notebooklm login` interactivo de una sola vez, pon `NOTEBOOKLM_HEADLESS_REAUTH=1` y la
investigación profunda puede refrescar su propia sesión sin una ventana de navegador visible —
apto para ejecuciones programadas o no interactivas en un servidor. El modo `fast` no necesita
login adicional.

**¿Qué diferencia hay aquí entre la memoria local y un cuaderno de NotebookLM?**
La memoria local es un puñado de ficheros Markdown cortos que se cargan en *cada* ejecución
(identidad, reglas duras, correcciones de método, trabajo en curso) — mantenla pequeña, la pagas
cada sesión. Un cuaderno es el corpus de referencia grande (procedimientos, sintaxis de comandos,
gotchas, diseño estable) que solo cuesta tokens cuando lo consultas. Un hecho vive exactamente en
un sitio.

**¿Cuándo NO debería usar la investigación de NotebookLM?**
Cuando ya sabes dónde vive un dato concreto — una consulta directa es más barata y más rápida.
Recuerda además que las respuestas son *fieles al corpus, no verdad verificada* (fundamentar no es
verificar), y que la investigación es asíncrona con latencia de minutos. Úsalo como tubería para la
recolección amplia, y que después el agente verifique las afirmaciones que sostienen la decisión.

**¿Es esto un producto oficial de Google o de NotebookLM?**
No. Es un flujo de trabajo independiente y de código abierto (AGPL-3.0-or-later) construido sobre la CLI no
oficial `notebooklm-py` de Teng Lin (<https://github.com/teng-lin/notebooklm-py>, MIT); probado con
notebooklm-py 0.8.2. No está afiliado a Google ni a NotebookLM, ni respaldado ni soportado por ellos.
*Nota fechada, 2026-09-23.* Google renombró el producto a Gemini Notebook el 2026-07-16 (Fuente:
[blog.google](https://blog.google/innovation-and-ai/products/gemini-notebook/notebooklm-gemini-notebook/)); los nombres en este repositorio y en la CLI no cambian. Las notas de
la versión 0.8.2 de aguas arriba dicen de sus propios transportes que «both backends rely on
undocumented Google APIs and may change without notice» (Fuente: [notebooklm-py v0.8.2
release](https://github.com/teng-lin/notebooklm-py/releases/tag/v0.8.2)).

---

## Parte de un conjunto más amplio de herramientas abiertas

Este es uno de los proyectos de un cuerpo más amplio de herramientas abiertas de Fernando Aporta
Franco. Es el complemento práctico de mantener un **corpus citable y legible por máquina**: un
sistema de conocimiento que mantiene el material de referencia de un agente estructurado,
consultable y barato de traer — la misma disciplina que la Generative Engine Optimization (GEO)
le pide a cualquier contenido que quieras que los motores de respuesta con IA encuentren y citen.

- [The GEO Handbook](https://github.com/ferinazumaDEV/generative-engine-optimization-handbook) — la referencia abierta sobre cómo conseguir que los motores de respuesta con IA (ChatGPT, Perplexity, Google AI Overviews, Gemini, Copilot) citen tu contenido.
- [typedout](https://github.com/ferinazumaDEV/typedout) — salida estructurada fiable desde OpenAI y Anthropic, con una interfaz de proveedor para los demás: JSON validado contra esquema, con reparación tolerante y reintentos, para convertir respuestas de modelo en datos legibles por máquina.
- [politeclient](https://github.com/ferinazumaDEV/politeclient) — un cliente HTTP cuidadoso y bien educado para Python (reintentos, límite de peticiones por host, caché, paginación) para el lado de descargar e ingerir al construir un corpus.
- Hub y escritura: [zentimes.es](https://zentimes.es).

Por [ferinazumaDEV](https://github.com/ferinazumaDEV).

---

## Licencia

Licenciado bajo la **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)** — ver [LICENSE](LICENSE).

Copyright (C) 2026 Fernando Aporta Franco

**Qué significa esto:** puedes usar, estudiar, modificar y compartir este software libremente, pero
**si lo distribuyes —o ejecutas una versión modificada como servicio en red (SaaS)— tienes que
publicar tu código fuente correspondiente completo bajo los mismos términos de la AGPL-3.0-or-later.** No se
puede cerrar el código. Esto es deliberado: el proyecto es público para compartirse, no para
volverse propietario.

<!-- provenance-fingerprint: nbkb-ec948d2d85 (AGPL-3.0-or-later, github.com/ferinazumaDEV/notebooklm-kb-system) -->
