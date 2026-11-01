# Despertador de Supabase — BIODCORE

Este repositorio contiene **dos archivos**: un trabajo de GitHub Actions y el
script que llama, para que el proyecto de Supabase de BIODCORE no se enfríe.

**Aquí no hay código de BIODCORE, ni datos, ni credenciales.** Es público por
un motivo concreto y es el único que importa: **en un repositorio público los
minutos de Actions son ilimitados**, y este trabajo los gasta a manos llenas.
En uno privado GitHub regala 2.000 al mes, así que una sola ejecución de 340
minutos se llevaría el 17% de la cuota mensual. No cabría de ninguna manera.

## Qué hace, y por qué dos llamadas

Supabase enfría el proyecto cuando no se usa. Medido el 17 de septiembre de
2026, cuatro consultas seguidas contra la base:

| | Tiempo |
|---|---|
| consulta 1 (en frío) | **34.509 ms** |
| consulta 2 | 1.754 ms |
| consulta 3 | 406 ms |
| consulta 4 | 391 ms |

Treinta y cuatro segundos y medio. Netlify corta mucho antes, así que quien
abría la aplicación tras un rato de inactividad no veía una pantalla lenta: no
veía pantalla.

Se llama a **dos** servicios, y ésa fue la primera corrección: una versión
anterior sólo consultaba `/auth/v1/health`, mantenía despierta la autenticación
y dejaba la **base de datos** congelándose — que es donde estaban los treinta y
cuatro segundos. El ping salía verde todas las veces mientras la aplicación se
caía.

La llamada a la base pide una columna de una fila y **espera un 401**. Ese
rechazo lo da PostgreSQL: las tablas tienen RLS activado sin políticas, así que
la llave pública no puede leer nada. Prueba que la conexión llegó hasta la base
—que es lo que la mantiene caliente— y de paso verifica que RLS sigue puesto.
**Un 200 ahí sería una emergencia.**

## Y AUN ASÍ LA BASE ESTABA FRÍA EL 90% DEL TIEMPO

Esto es lo que se corrigió el **1 de noviembre de 2026**, y conviene que quede
escrito porque **no fallaba nada**.

El trabajo declara `cron: */5`, que son 288 ejecuciones al día. **GitHub
disparaba 5,7.** En los repositorios públicos el evento `schedule` es de mejor
esfuerzo y se descarta bajo carga. Medido sobre las 61 ejecuciones de los once
días anteriores:

| | |
|---|---|
| Ejecuciones al día | **5,7** · deberían ser 288 |
| Hueco mediano | **254 min** · 4 h 14 |
| Hueco máximo | 428 min · 7 h 08 |
| Huecos de más de 25 minutos | **60 de 60** |
| Conclusiones | **61 en VERDE** |

**Ninguna falló**, y ahí está la trampa: el ping salía verde todas las veces
mientras la base se pasaba el día congelándose. Es la misma clase de engaño que
la versión que sólo pingeaba la autenticación, y se descubre igual — midiendo,
no mirando la pestaña Actions.

Veinticinco minutos de reposo bastan para volver a enfriarse, así que con
huecos de cuatro horas **la base estaba fría el 90,3% del tiempo**: 232,5 horas
de las 257 medidas.

### No se arregla el intervalo: se arregla la DURACIÓN

Bajar el `cron` no sirve de nada —ya pide el mínimo que GitHub admite— y
añadir avisos tampoco: lo que falla es el disparador, no el ping.

Así que cada ejecución **deja de durar diez segundos y pasa a pingear durante
horas**. Con eso, lo que GitHub tiene que acertar no es «disparar cada cinco
minutos» sino «disparar una vez cada diecisiete horas», que es de sobra lo que
sí hace.

| Cobertura por disparo | Huecos sin cubrir, de los 60 medidos | |
|---|---|---|
| 10 s · lo de antes | **60 de 60** | fría el **90,3%** del tiempo |
| 340 min · un trabajo | 13 de 60 | fría el **2,8%** |
| **1.020 min · TRES** | **0 de 60** | |

**Son TRES trabajos encadenados y no uno largo** porque GitHub corta un trabajo
a las **seis horas**. Una ejecución entera puede durar mucho más, así que se
encadenan con `needs`: cada uno arranca cuando acaba el anterior.

### Verás ejecuciones CANCELADAS, y es lo normal

`cancel-in-progress` tira la ejecución en curso cuando entra una nueva: la nueva
toma el relevo en el acto y reinicia las diecisiete horas, que es lo que se
busca. En la pestaña Actions eso se ve como ejecuciones **canceladas**.

**No son fallos** — son la anterior cediendo el turno. Lo que sí hay que mirar
es que **haya una EN CURSO casi siempre**. Ésa es la señal buena, y no el color
de las de la lista.

Cada ejecución deja además su resumen: cuántos pings hizo, cuántos minutos
cubrió y cuál fue la peor respuesta de la base.

## Puesta en marcha

En **Settings → Secrets and variables → Actions → New repository secret**, de
este repositorio:

| Secreto | Qué es |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | La dirección del proyecto en Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | La llave pública (`anon`) |

Después, **Actions → Mantener despierto Supabase → Run workflow** para
comprobarlo sin esperar al reloj. El registro debe decir algo como:

```
13:53:28  auth 200 en   448 ms   base 401 en   1190 ms
13:53:43  auth 200 en   372 ms   base 401 en   1127 ms
```

**Un `push` a `main` también lo arranca**, que es lo que permite comprobar un
cambio en el acto — y lo que reinicia el contador de los 60 días.

## Que aquí no entre nunca la llave de servicio

La llave `anon` **es pública por diseño**: viaja en el JavaScript que descarga
cualquier navegador que abra la aplicación, y con RLS sin políticas no da acceso
a nada. Por eso puede estar en los secretos de un repositorio público sin que
eso cambie nada.

`SUPABASE_SERVICE_ROLE_KEY` es otra cosa: **se salta RLS entera** y no pinta en
un despertador. No debe aparecer aquí bajo ningún concepto.

## GitHub lo desactiva solo a los 60 días

En un repositorio público, GitHub desactiva los workflows programados cuando el
repositorio lleva **60 días sin actividad**. Éste no va a tener ninguna —son dos
archivos que no se tocan— así que va a pasar.

Llega un correo de aviso antes. Hay dos salidas:

- entrar en **Actions** y reactivarlo, que es un clic; o
- adelantarse cada par de meses con un commit vacío:

```bash
git commit --allow-empty -m "Mantener el programador activo"
git push
```

**Si un día notas que la aplicación vuelve a tardar medio minuto en abrir por la
mañana**, mira esto primero, y mira que haya una ejecución **en curso**. Son las
dos causas probables, y ninguna avisa de otra forma: el workflow no falla,
simplemente deja de ejecutarse.
