# ChocoMake

Herramienta de construcción (build tool) escrita en Odin.

> [!WARNING]
> **⚠️ PROYECTO EN DESARROLLO EXPERIMENTAL ⚠️**
> 
> Este proyecto está en fase experimental y actualmente en desarrollo activo:
> - ✅ **Windows**: Funciona correctamente
> - ⚠️ **Linux**: puede presentar problemas
> - 🚧 **Características**: Algunas funcionalidades pueden cambiar sin previo aviso
> - 🐛 **Bugs**: Es posible encontrar errores y comportamientos inesperados
> 
> **No se recomienda para uso en producción.** Úsalo bajo tu propio riesgo.

## Uso

```bash
chocomake <comando> <target> [-f:<flag>]
```

**Ejemplos:**
```bash
chocomake build windows           # Construir target windows
chocomake build windows -f:debug  # Construir con flag debug
chocomake run windows              # Ejecutar target windows
```

## Archivo de Configuración

El archivo de configuración puede llamarse `ChocoMake`, `chocomake` o `chocofile`.

> [!NOTE]
> ChocoMake busca los archivos en ese orden. Si encuentra uno, usa ese y no busca los demás.

### Estructura Básica

```
default: <target_por_defecto>

# Variables
name = valor

# Flags
flags : [debug, release]

# Targets
[nombre_target]
build:
    comando1
    comando2
run:
    comando
```

## Variables

> [!WARNING]
> **Las variables NO se pueden sobreescribir.** Si intentas declarar una variable que ya existe, la segunda declaración será ignorada.

### Variables Normales
```
name = ChocoMake
project = mi_proyecto
```

**Ejemplo de error común:**
```
name = ChocoMake
name = ChocoMake2  # ❌ Esto será ignorado, name seguirá siendo "ChocoMake"
```

### Variables de Entorno

```
env.OS
env.PATH
```

> [!IMPORTANT]
> **Comportamiento de `env.VARIABLE`:**
> - `env.OS` crea una variable llamada `OS` con el valor de la variable de entorno del sistema
> - Si la variable de entorno no existe, no se crea ninguna variable
> - El orden de declaración importa debido a la regla de no sobreescritura

**Patrón de Fallback:**

Puedes usar el orden de declaración para crear valores por defecto (fallback):

```
# ✅ Correcto: Fallback si OS no existe en el entorno
env.OS
OS = Windows_NT

# Si la variable de entorno OS existe, se usa su valor (env.OS la crea primero)
# Si NO existe, env.OS no crea nada, entonces OS = Windows_NT se ejecuta como fallback
```

```
# ❌ Incorrecto: El fallback no funcionará
OS = Windows_NT
env.OS

# La variable OS ya fue creada con "Windows_NT"
# env.OS intenta crear OS pero no puede sobreescribir, se ignora
```

**Ejemplo práctico:**
```
# Intentar cargar desde variables de entorno primero
env.COMPILER
env.BUILD_MODE

# Definir valores por defecto (fallback)
COMPILER = odin
BUILD_MODE = debug

# Si las variables de entorno existen, se usan
# Si no existen, se usan los valores por defecto
```

### Variables con Referencias
Usa `{nombre_variable}` para referenciar otras variables:
```
output = build/{project}/{name}.exe
```

### Funciones

#### `now(formato)`
Obtiene fecha/hora actual. Formatos: `YYYY`, `MM`, `DD`, `hh`, `mm`, `ss`
```
date = {now(YYYY-MM-DD)}
year = {now(YYYY)}
```

#### `read_file(ruta)`
Lee el contenido de un archivo:
```
version = {read_file(VERSION)}
```

#### `cmd@<comando>`
Ejecuta un comando y captura su salida:
```
commit_hash = {cmd@git rev-parse --short HEAD}
hello = {cmd@cmd /c "echo hola"}
```

### Selectores

Seleccionan valores basados en flags o el target actual (group):

```
win_flag: selector flags
   debug: -debug
   release: -o:speed

path_selector: selector group
   windows: build/windows
   linux: build/linux
```

**Fuentes:**
- `flags` - Selecciona según el flag pasado con `-f:`
- `group` - Selecciona según el target actual

> [!TIP]
> Si no se especifica un flag con `-f:`, se usa el primer flag de la lista `flags : [...]` por defecto.

> [!NOTE]
> Los selectores con `group` se resuelven según el nombre del target que se está ejecutando (ej: `[windows]` → group = "windows").

### Plantillas (Templates)

Generan múltiples valores expandiendo un patrón:

```
collections: template -collection:key:a1
     thirdparty: src/third_party
     lib2: src/lib2

# Genera: -collection:thirdparty:src/third_party -collection:lib2:src/lib2
```

Con múltiples valores:
```
collections2: template -collection:key:a1:a2
     thirdparty: [src/third_party, banana]
     lib2: [src/lib2, apple]
```

Filtrar entradas específicas:
```
{collections[lib2]}  # Solo expande lib2
```

## Targets

Los targets definen conjuntos de comandos. Bloques disponibles: `build`, `run`, `copy`, `clean`.

```
[windows]
build:
    odin build src -out:{path_selector}/{name}.exe
run:
    {path_selector}/{name}.exe

[linux]
build:
    odin build src -out:{path_selector}/{name} -target:linux_amd64
```

### Comandos Especiales

#### `@call <target>`
Llama a otro target:
```
[all]
build:
    @call windows
    @call linux
```

Llamar con comando específico:
```
@call windows:run
```

#### `@hook <comando>`
Ejecuta un comando diferente en el mismo target:
```
@hook clean
```

### Operaciones de Archivos

#### Copiar archivos
```
src/file.txt <-> dest/file.txt
```

#### Mover archivos
```
src/file.txt -> dest/file.txt
```

#### Eliminar archivos/directorios
```
delete build/temp
delete *.log
```

> [!CAUTION]
> Las operaciones de eliminación (`delete`) son permanentes y no se pueden deshacer. Usa con cuidado.

> [!NOTE]
> Todas las operaciones de archivos soportan wildcards (`*`) para operaciones en lote.

## Ejemplo Completo

```
default: all
env.OS

flags : [debug, release]

name = MiApp
version = {read_file(VERSION)}


win_flag: selector flags
   debug: -debug
   release: -o:speed

path_selector: selector group
   windows: build/windows
   linux: build/linux

[windows]
build:
    odin build src {win_flag} -out:{path_selector}/{name}.exe
run:
    {path_selector}/{name}.exe
clean:
    delete {path_selector}/*

[linux]
build:
    odin build src {win_flag} -out:{path_selector}/{name} -target:linux_amd64
run:
    ./{path_selector}/{name}

[all]
build:
    @call windows
    @call linux
```

## Compilar ChocoMake

```bash
odin build src -out:ChocoMake.exe
```

## Notas Importantes

> [!NOTE]
> **Comportamiento por diseño:**

- **Variables inmutables**: Una vez declarada una variable, no se puede cambiar su valor (por diseño)
- **Variables automáticas**: `commit_hash_short` y `commit_hash` se crean automáticamente al ejecutar ChocoMake
- **Orden de declaración**: 
  - Las variables deben declararse antes de usarse en referencias
  - Para fallbacks con `env.VAR`, declara `env.VAR` PRIMERO, luego el valor por defecto
- **Selectores con flags**: Si no se especifica `-f:`, se usa el primer flag de la lista por defecto
- **Variables de entorno**: Si `env.VAR` no existe en el sistema, no se crea ninguna variable
